`timescale 1ns / 1ps

// ============================================================================
// Control Unit  (하위 모듈 정의까지 이 파일에 모두 포함)
//
//   control_unit
//     ├ stopwatch_control_unit
//     ├ watch_control_unit
//     ├ SR04_controller  └ tick_us
//     └ dht11            └ tick_gen
//
//  - sw로 화면(sel), display_mode, save를 만든다
//  - 디바운스된 버튼을 선택된 모드로만 전달한다
//  - sr04 / dht11 은 선택된 모드에서 d_btn_R로 start
//  - dht11 값은 done && valid 일 때만 저장해서 내보낸다
//
//  스위치
//    sw[0] : display_mode (시계: 초:ms <-> 시:분,  dht11: 온도 <-> 습도)
//    sw[1] : watch
//    sw[2] : sr04
//    sw[3] : dht11
//    sw[4] : save (stopwatch 캡처)
//    (우선순위 sw[3] > sw[2] > sw[1], 전부 꺼지면 stopwatch)
//
//  버튼 (btn_debounce를 거친 1클럭 펄스라고 가정)
//    stopwatch : L=run/stop, R=clear, U=mode, D=min_inc
//    watch     : L=left, R=right, U=inc, D=dec, C=clear
//    sr04/dht11: R=start
// ============================================================================
module control_unit (
    input        clk,
    input        reset,
    input  [4:0] sw,

    // 디바운스된 버튼
    input        d_btn_L,
    input        d_btn_R,
    input        d_btn_U,
    input        d_btn_D,
    input        d_btn_C,

    // ascii_decoder 명령 (1클럭 펄스)
    input        com_run,
    input        com_clear,
    input        com_mode,
    input        com_opt,
    input        com_lm,
    input        com_rm,
    input        com_inc,
    input        com_dec,
    input        com_dht11,
    input        com_sr04,
    input        com_get,      // /get : 현재 화면의 값을 PC로 전송

    // fnd / mux
    output reg [1:0] sel,
    output           display_mode,
    output           save,

    // stopwatch datapath
    output           sw_run_stop,
    output           sw_clear,
    output           sw_mode,
    output           sw_min_inc,

    // watch datapath
    output           wt_hour_inc_en,
    output           wt_hour_dec_en,
    output           wt_min_inc_en,
    output           wt_min_dec_en,

    // sr04 (센서 핀 + 거리값)
    input            echo,
    output           trigger,
    output [8:0]     sr_dist,
    output reg       req_sr,      // ascii_sender 요청 (1클럭 펄스)

    // dht11 (센서 핀 + 저장된 온습도)
    inout            dht11_io,
    output [7:0]     temp_int,
    output [7:0]     temp_dec,
    output [7:0]     hum_int,
    output [7:0]     hum_dec,
    output reg       req_dht,     // ascii_sender 요청 (1클럭 펄스)

    // ascii_sender 요청: /get 으로 stopwatch / watch 값 전송
    output           req_sw,
    output           req_wt
);

    // ------------------------------------------------------------------
    // 1) 모드 선택
    // ------------------------------------------------------------------
    always @(*) begin
        case (sw[3:1])      // {sw[3], sw[2], sw[1]}
            3'b000:  sel = 2'd0;  // stopwatch
            3'b001:  sel = 2'd1;  // watch
            3'b010:  sel = 2'd2;  // sr04
            3'b011:  sel = 2'd2;  // sw[2] 우선 -> sr04
            3'b100:  sel = 2'd3;  // dht11
            3'b101:  sel = 2'd3;  // sw[3] 우선 -> dht11
            3'b110:  sel = 2'd3;  // sw[3] 우선 -> dht11
            3'b111:  sel = 2'd3;  // sw[3] 우선 -> dht11
            default: sel = 2'd0;
        endcase
    end

    assign display_mode = sw[0];
    assign save         = sw[4];

    // ------------------------------------------------------------------
    // 2) 버튼 게이팅 (선택된 모드에만 전달)
    // ------------------------------------------------------------------
    wire is_stopwatch = (sel == 2'd0);
    wire is_watch     = (sel == 2'd1);
    wire is_sr04      = (sel == 2'd2);
    wire is_dht11     = (sel == 2'd3);

    // 버튼과 PC 명령을 같은 입력으로 합친다 (둘 다 1클럭 펄스)
    //   stopwatch : L=/run   R=/clear  U=/mode  D=/opt
    //   watch     : L=/lm    R=/rm     U=/inc   D=/dec   C=/clear
    wire sw_btn_L = (d_btn_L | com_run)   & is_stopwatch;
    wire sw_btn_R = (d_btn_R | com_clear) & is_stopwatch;
    wire sw_btn_U = (d_btn_U | com_mode)  & is_stopwatch;
    wire sw_btn_D = (d_btn_D | com_opt)   & is_stopwatch;

    wire wt_btn_L = (d_btn_L | com_lm)    & is_watch;
    wire wt_btn_R = (d_btn_R | com_rm)    & is_watch;
    wire wt_btn_U = (d_btn_U | com_inc)   & is_watch;
    wire wt_btn_D = (d_btn_D | com_dec)   & is_watch;
    wire wt_btn_C = (d_btn_C | com_clear) & is_watch;

    // 센서는 PC 명령(/sr04, /dht11)이면 화면 모드와 상관없이 측정한다
    wire w_sr_start  = (d_btn_R & is_sr04)  | com_sr04;
    wire w_dht_start = (d_btn_R & is_dht11) | com_dht11;

    wire w_sr_done;

    // ------------------------------------------------------------------
    // 3) stopwatch / watch control unit
    // ------------------------------------------------------------------
    stopwatch_control_unit U_STOPWATCH_CU (
        .clk       (clk),
        .reset     (reset),
        .i_run_stop(sw_btn_L),
        .i_clear   (sw_btn_R),
        .i_mode    (sw_btn_U),
        .i_min_inc (sw_btn_D),
        .o_run_stop(sw_run_stop),
        .o_clear   (sw_clear),
        .o_mode    (sw_mode),
        .o_min_inc (sw_min_inc)
    );

    watch_control_unit U_WATCH_CU (
        .clk         (clk),
        .reset       (reset),
        .display_mode(display_mode),
        .left_move   (wt_btn_L),
        .right_move  (wt_btn_R),
        .inc         (wt_btn_U),
        .dec         (wt_btn_D),
        .clear       (wt_btn_C),
        .hour_inc_en (wt_hour_inc_en),
        .hour_dec_en (wt_hour_dec_en),
        .min_inc_en  (wt_min_inc_en),
        .min_dec_en  (wt_min_dec_en),
        .sec_inc_en  (),   // datapath에서 안 씀
        .sec_dec_en  (),
        .msec_inc_en (),
        .msec_dec_en ()
    );

    // ------------------------------------------------------------------
    // 4) sr04
    // ------------------------------------------------------------------
    SR04_controller U_SR04_CNTL (
        .clk     (clk),
        .reset   (reset),
        .start   (w_sr_start),
        .echo    (echo),
        .trigger (trigger),
        .done    (w_sr_done),
        .distance(sr_dist)
    );

    // ------------------------------------------------------------------
    // 5) dht11 + 값 저장 (측정 성공 done && valid 일 때만 갱신)
    // ------------------------------------------------------------------
    wire [15:0] w_temp, w_hum;
    wire        w_dht_done, w_dht_valid;

    dht11 U_DHT11 (
        .clk        (clk),
        .reset      (reset),
        .start      (w_dht_start),
        .temperature(w_temp),
        .humidity   (w_hum),
        .done       (w_dht_done),
        .valid      (w_dht_valid),
        .dht11_io   (dht11_io)
    );

    reg [15:0] temp_reg, hum_reg;

    always @(posedge clk or posedge reset) begin
        if (reset) begin
            temp_reg <= 16'd0;
            hum_reg  <= 16'd0;
        end else if (w_dht_done && w_dht_valid) begin
            temp_reg <= w_temp;
            hum_reg  <= w_hum;
        end
    end

    assign temp_int = temp_reg[15:8];
    assign temp_dec = temp_reg[7:0];
    assign hum_int  = hum_reg[15:8];
    assign hum_dec  = hum_reg[7:0];

    // ------------------------------------------------------------------
    // 6) PC 명령으로 시작한 측정만, 끝난 뒤 ascii_sender에 전송 요청
    //    (버튼으로 한 측정은 화면에만 표시하고 PC로는 보내지 않는다)
    //    req_*는 값이 저장된 다음 클럭에 1클럭 펄스로 나간다.
    // ------------------------------------------------------------------
    // /get : 지금 보고 있는 화면(모드)의 값을 PC로 보낸다
    assign req_sw = com_get & is_stopwatch;
    assign req_wt = com_get & is_watch;

    reg sr_pending, dht_pending;

    always @(posedge clk or posedge reset) begin
        if (reset) begin
            sr_pending  <= 1'b0;
            dht_pending <= 1'b0;
            req_sr      <= 1'b0;
            req_dht     <= 1'b0;
        end else begin
            req_sr  <= 1'b0;
            req_dht <= 1'b0;

            if (com_sr04)  sr_pending  <= 1'b1;
            if (com_dht11) dht_pending <= 1'b1;

            if (w_sr_done && sr_pending) begin
                sr_pending <= 1'b0;
                req_sr     <= 1'b1;
            end

            if (w_dht_done && dht_pending) begin
                dht_pending <= 1'b0;
                if (w_dht_valid) req_dht <= 1'b1;  // 체크섬 실패면 보내지 않음
            end

            // /get : 센서 화면이면 새로 측정하지 않고 마지막으로 저장된 값을 바로 전송
            if (com_get && is_sr04)  req_sr  <= 1'b1;
            if (com_get && is_dht11) req_dht <= 1'b1;
        end
    end

endmodule


// ============================================================================
// stopwatch_control_unit (기존 코드 그대로)
// ============================================================================
module stopwatch_control_unit (
    input  clk,
    input  reset,
    input  i_run_stop,
    input  i_clear,
    input  i_mode,
    input  i_min_inc,
    output o_run_stop,
    output o_clear,
    output o_mode,
    output o_min_inc
);

    parameter STOP = 0, RUN = 1, CLEAR = 2, MODE = 3;
    reg [1:0] state_c, state_n;
    reg run_stop_reg, run_stop_next,clear_reg,clear_next,mode_reg,mode_next;
    reg min_inc_next;

    // output Combinational Logic: 우선 o_mode = 0 으로 고정하고, 차후 구현예정
    //assign {o_clear, o_run_stop, o_mode} =  (state_c == STOP) ? 3'b000 : 
    //                                        (state_c == RUN) ? 3'b010 : 
    //                                        (state_c == CLEAR) ? 3'b100 : 
    //                                       (state_c == MODE) ? 3'b000 : 3'b000;

    assign o_run_stop =run_stop_reg;
    assign o_clear=clear_reg;
    assign o_mode=mode_reg;
    assign o_min_inc= min_inc_next;

    always @(posedge clk, posedge reset) begin
        if (reset) begin 
            state_c <= STOP;
            run_stop_reg <=1'b0;
            clear_reg <=1'b0;
            mode_reg <=1'b0;
        end else begin 
            state_c <= state_n;
            run_stop_reg <=run_stop_next;
            clear_reg<=clear_next;
            mode_reg<=mode_next;
        end
        end


    // next_state & output Combinational Logic
    always @(*) begin
        state_n = state_c;
        run_stop_next=run_stop_reg;
        clear_next=clear_reg;
        mode_next=mode_reg;
        min_inc_next = 0; 

        case (state_c)
            STOP: begin
                //moore output
                run_stop_next = 1'b0;
                clear_next = 1'b0;
                if(i_min_inc) begin
                    min_inc_next=1;
                end
                if (i_run_stop) state_n = RUN;
                else if (i_clear) state_n = CLEAR;
                else if (i_mode) state_n = MODE;
                else state_n = state_c;
            end
            RUN: begin
                run_stop_next = 1'b1;
                if (i_run_stop) state_n = STOP;
                else state_n = state_c;
            end
            CLEAR: begin
                clear_next = 1'b1;
                state_n = STOP;
            end
            MODE: begin
                mode_next = ~mode_reg;
                state_n = STOP;
            end
        endcase
    end

endmodule


// ============================================================================
// watch_control_unit (기존 코드 그대로)
// ============================================================================
module watch_control_unit (
    input clk,
    input reset,
    input display_mode,
    input left_move,
    input right_move,
    input inc,
    input dec,
    input clear,
    output hour_inc_en,
    output hour_dec_en,
    output min_inc_en,
    output min_dec_en,
    output sec_inc_en,
    output sec_dec_en,
    output msec_inc_en,
    output msec_dec_en

);

    localparam HOUR = 0, MIN = 1, SEC = 2, MSEC = 3, IDLE = 4;

    reg [2:0] state_c, state_n;

    reg hour_inc_en_next;
    reg hour_dec_en_next;
    reg min_inc_en_next;
    reg min_dec_en_next;


    assign hour_inc_en = hour_inc_en_next;
    assign hour_dec_en = hour_dec_en_next;
    assign min_inc_en  = min_inc_en_next;
    assign min_dec_en  = min_dec_en_next;



    always @(posedge clk, posedge reset) begin
        if (reset|clear) begin
            state_c <= IDLE;
        end else begin
            state_c <= state_n;
        end
    end

    always @(*) begin
        state_n = state_c;
        hour_inc_en_next = 0;
        hour_dec_en_next = 0;
        min_inc_en_next  = 0;
        min_dec_en_next  = 0;

        
        case (state_c)
            IDLE: begin
                if (display_mode) state_n = HOUR;
                else state_n = SEC;
            end

            HOUR: begin
                if ((left_move) && (!right_move)) state_n = HOUR;
                if ((!left_move) && (right_move)) state_n = MIN;
                if (inc) hour_inc_en_next = 1;
                if (dec) hour_dec_en_next = 1;


            end

            MIN: begin
                if ((left_move) && (!right_move)) state_n = HOUR;
                if ((!left_move) && (right_move)) state_n = MIN;
                if (inc) min_inc_en_next = 1;
                if (dec) min_dec_en_next = 1;
            end

            SEC: begin
                if(!display_mode) begin
                if ((left_move) && (!right_move)) state_n = SEC;
                if ((!left_move) && (right_move)) state_n = MSEC; 
                end 
                else state_n = HOUR;
            end

            MSEC: begin
                if(!display_mode) begin
                if ((left_move) && (!right_move)) state_n = SEC;
                if ((!left_move) && (right_move)) state_n = MSEC;
                end else state_n = HOUR;
            end
            default: state_n = IDLE;
        endcase


    end


endmodule


// ============================================================================
// SR04_controller (기존 코드 그대로)
// ============================================================================
module SR04_controller (

    input clk,
    input reset,
    input start,            // btn->fpga
    input echo,             // sensor->fpga
    output reg trigger,     // fpga->sensor
    output done,            // measurement complete (1-clk pulse)
    output [8:0] distance  //max 400 9bit->0~511
);




    wire w_tick_us;
    // fsm control_unit
    localparam [2:0] IDLE = 0, START = 1, WAIT = 2, COUNT = 3, DISTANCE = 4;
    reg [2:0] c_state, n_state;
    reg run_stop;
    reg clear;
    reg [$clog2(58*400)-1:0] counter_reg, counter_next;   // 1cm = 58us 400cm = 58*400

    reg [8:0] distance_reg, distance_next;
    reg done_reg, done_next;

    assign distance = distance_reg;
    assign done = done_reg;

    tick_us U_TICK_US (
        .clk(clk),
        .reset(reset),
        .run_stop(run_stop),
        .clear(clear),
        .o_tick_us(w_tick_us)
    );  // 1us -> tick_us

   /* ila_0 U_ILA (
        .clk(clk),
        .probe0(start),
        .probe1(trigger),
        .probe2(echo),
        .probe3(c_state)
    );
    */



    always @(posedge clk, posedge reset) begin
        if (reset) begin
            c_state <= IDLE;
            counter_reg <= 0;
            distance_reg <= 0;
            done_reg <= 0;

        end else begin
            c_state      <= n_state;
            counter_reg  <= counter_next;
            distance_reg <= distance_next;
            done_reg     <= done_next;
        end
    end

    always @(*) begin
        n_state = c_state;
        counter_next = counter_reg;
        distance_next = distance_reg;
        done_next = 0;

        run_stop = 1'b0;
        clear    = 1'b0;
        trigger  = 1'b0;

        case (c_state)
            IDLE: begin    //버튼을 누르기 전에는 trigger를 내보내면 안 되니까, 아무것도 안 하고 머무는 상태가 필요
                run_stop = 1'b0;
                clear    = 1'b1;  
                if (start) begin  // fpga start 
                    n_state = START;
                    counter_next = 0;
                end
            end

            START: begin    // 타이머 가동 + 센서에 명령
                run_stop = 1'b1;
                clear    = 1'b0;
                trigger  = 1'b1;  // sensor

                if (w_tick_us) begin
                    if (counter_reg == 11) begin  // min 10us, margin 11us
                        n_state = WAIT;
                        counter_next = 0;
                        clear = 1'b1;
                    end else begin
                        counter_next = counter_reg + 1;
                    end
                end

            end

            WAIT: begin    // 센서가 초음파 8번을 쏘는 시간(약 200us 이상)은 거리와 무관. 이 구간은 재면 안 되므로 타이머를 멈추고 0으로 묶어둡
                trigger = 1'b0;
                clear = 1'b1;
                run_stop = 1'b0;
                if (echo) begin
                    n_state = COUNT;
                end
                counter_next = 0;
            end


            COUNT: begin     // echo time 측정, COUNT때만 echo가 1 
                run_stop = 1'b1;
                trigger = 1'b0;
                clear = 1'b0;

                if (w_tick_us) begin
                    counter_next = counter_reg + 1;
                end

                if (!echo) n_state = DISTANCE;
            end
            DISTANCE: begin  //  echo time을 거리로 변환 

                distance_next = counter_reg / 58;
                done_next = 1;
                n_state = IDLE;

            end

            default: n_state = IDLE;
        endcase
    end
endmodule

module tick_us (
    input clk,
    input reset,
    input run_stop,
    input clear,
    output reg o_tick_us
);


    parameter F_COUNT = 100;
    reg [$clog2(F_COUNT) - 1:0] counter_reg;

    always @(posedge clk, posedge reset) begin
        if (reset | clear) begin
            counter_reg <= 0;
            o_tick_us   <= 1'b0;
        end else begin
            if (run_stop) begin  //?
                counter_reg <= counter_reg + 1;
                if (counter_reg == F_COUNT - 1) begin
                    counter_reg <= 0;
                    o_tick_us   <= 1'b1;
                end else o_tick_us <= 1'b0;
            end
        end
    end
endmodule


// ============================================================================
// dht11 (기존 코드 그대로, 주석 처리된 개선본은 제외)
// ============================================================================
module dht11 (

    input clk,
    input reset,
    input start,
    output [15:0] temperature,
    output [15:0] humidity,
    output reg done,
    output reg valid,
    inout dht11_io  // 1: FPGA-> DHT11, 0: FPGA<-DHT11
);

    localparam [2:0] IDLE = 0, START =1, WAIT =2, SYNC =3, DATA = 4, STOP = 5;
    reg [2:0] c_state, n_state;

    wire tick_us;
    reg [$clog2(19000)-1:0] tick_count_reg, tick_count_next; //START 구간에서 라인을 Low로 몇 µs 유지 19ms=19000us
    reg io_control;
    reg dht11_io_reg, dht11_io_next; //FPGA->line FPGA가 dht11_io 핀에 연결된 전선 한 가닥(line)에 내보낼 값
    assign dht11_io = (io_control) ? (dht11_io_reg) : 1'bz;


    tick_gen U_TICK_GEN_US (
        .clk(clk),
        .reset(reset),
        .us_tick(tick_us)
    );

    // metastability 2-stage synchronizer 
    reg dht_sync_0, dht_sync_1;
    always @(posedge clk or posedge reset) begin
        if (reset) begin
            dht_sync_0 <= 1'b1;
            dht_sync_1 <= 1'b1;
        end else begin
            dht_sync_0 <= dht11_io;
            dht_sync_1 <= dht_sync_0;
        end
    end
    //Pull-up Resistor에 의해 평상시(통신 안할때) 항상 High(1) 상태를 유지


    reg dht_reg, dht_next; // line → FPGA (입력용),line에서 읽은 값의 이전 값
    reg fall_edge;         // negedge sensitivity 

    always @(*) begin
        dht_next = dht_sync_1;  //dht_next = dht11_io을 다음과 같이 변경
        fall_edge = (dht_reg== 1'b1) && (dht_next == 1'b0);
    end
    //past 1 , current 0 -> fall_edge 

    reg [39:0] data_shift_reg, data_shift_next; //40bit data
    reg [5:0] bit_cnt_reg, bit_cnt_next; // received bit count,몇 번째 비트인지 세는 카운터
    reg [15:0] high_time_reg, high_time_next; // high 유지 time 

    assign humidity = data_shift_reg[39:24];
    assign temperature = data_shift_reg[23:8];

    // Checksum calculation
    wire [7:0] checksum = data_shift_reg[39:32] + data_shift_reg[31:24] + 
                         data_shift_reg[23:16] + data_shift_reg[15:8];
    // humidity decimal/integer, temperature decimal/integer

    always @(posedge clk, posedge reset) begin
        if (reset) begin
            c_state <= IDLE;
            dht11_io_reg <= 1'b1;
            tick_count_reg <= 0;

            data_shift_reg <= 0;
            bit_cnt_reg <=0;
            high_time_reg <=0;
            dht_reg <=1'b1;
        end else begin
            c_state <= n_state;
            dht11_io_reg <= dht11_io_next;
            tick_count_reg <= tick_count_next;

            data_shift_reg <= data_shift_next;
            bit_cnt_reg <=bit_cnt_next;
            high_time_reg <=high_time_next;
            dht_reg <=dht_next;
        end
    end

    always @(*) begin
        n_state = c_state;
        dht11_io_next = dht11_io_reg;
        tick_count_next = tick_count_reg;
        
        data_shift_next = data_shift_reg;
        bit_cnt_next = bit_cnt_reg;
        high_time_next = high_time_reg;

        io_control = 1'b1;
        done    =1'b0;
        valid =1'b0;


        case (c_state)
            IDLE: begin
                dht11_io_next = 1'b1; //  pull up when 1 ->nothing request
                io_control = 1'b0;  // 0 or 1  상관없음 
                tick_count_next = 0;
                bit_cnt_next = 0;
                if (start) begin
                    n_state = START;
                end
            end
            START: begin
                dht11_io_next = 1'b0; //request 1->0
                io_control = 1'b1;  //FPGA가 선을 직접 Low로 끌어내려야 하기 때문
                if (tick_us) begin
                    if (tick_count_reg == 19_000) begin
                        tick_count_next = 0;
                        n_state = WAIT;  //1us unit
                    end else tick_count_next = tick_count_reg + 1;
                end
            end

            WAIT: begin
                dht11_io_next = 1'b1;
                io_control = 1'b0; // START 종료 후 바로 High-Z로 변환하여 DHT11 수신 준비

                if (tick_us)
                    if (tick_count_reg == 30) begin
                        tick_count_next = 0;
                        n_state = SYNC;
                    end else tick_count_next = tick_count_reg + 1;
            end

            SYNC: begin
                io_control = 0;  //  sensor signal received
                if (tick_us) begin
                        tick_count_next = tick_count_reg + 1;
                end
            //high & fall_edge n_state:DATA    
            if (fall_edge && (tick_count_reg > 100)) begin  // trouble shooting  && (tick_count_reg > 100)
                    tick_count_next = 0;
                    bit_cnt_next    = 0;
                    high_time_next  = 0;
                    n_state         = DATA;
                end
                
            end  
            
            DATA: begin
                io_control = 1'b0; //  sensor signal received
                if(tick_us)begin
                    tick_count_next = tick_count_reg +1;
                    //high signal holding time 
                    if(dht_next ==1'b1) begin
                        high_time_next = high_time_reg +1;
                    end
                end 

                if(fall_edge)begin  //data 판별 
                    tick_count_next = 0;
                    high_time_next = 0;
                    bit_cnt_next = bit_cnt_reg +1; 

                    if(high_time_reg>40) begin
                        data_shift_next = {data_shift_reg[38:0],1'b1};
                    end else begin
                        data_shift_next = {data_shift_reg[38:0],1'b0};
                    end
                    if(bit_cnt_reg == 39) begin
                        n_state = STOP;
                    end
                end
            end

            STOP: begin
                io_control = 1'b0;
                if (tick_us) begin
                    tick_count_next = tick_count_reg + 1;
                end
                
                if (tick_count_reg > 50) begin
                    done = 1'b1;
                    if (checksum == data_shift_reg[7:0]) begin
                        valid = 1'b1;
                    end else begin
                        valid = 1'b0;
                    end
                    n_state = IDLE;
                end
            end

        endcase

    end

endmodule


module tick_gen (
    input  clk,
    input  reset,
    output us_tick
);

    parameter F_COUNT = 100;
    reg [$clog2(F_COUNT) - 1:0] counter_reg;
    reg tick_reg;
    assign us_tick = tick_reg;

    always @(posedge clk, posedge reset) begin
        if (reset) begin
            counter_reg <= 0;
            tick_reg <= 0;
        end else begin
            counter_reg <= counter_reg + 1;
            if (counter_reg == F_COUNT - 1) begin
                tick_reg <= 1;
                counter_reg <= 0;
            end else tick_reg <= 0;
        end
    end
endmodule