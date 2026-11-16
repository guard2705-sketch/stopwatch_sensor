`timescale 1ns / 1ps

// ============================================================================
// ASCII Sender
//
//  "어떤 소스를 보낼지"를 요청 펄스(req_*)가 정한다.
//  화면에 보이는 모드(sel)와 무관하게, 요청된 소스의 값을 보낸다.
//
//  요청이 들어오면 그 순간의 값을 캡처하고, 문자열을 한 글자씩 FIFO에 push 한다.
//  (full 이면 대기, 전송 중(busy)에 들어온 요청은 무시)
//
//    req_sw   : stopwatch 시간   -> HH:MM:SS.mm\n      (12글자)
//    req_wt   : watch 시간       -> HH:MM:SS.mm\n      (12글자)
//    req_sr   : sr04 거리        -> D=123cm\n          ( 8글자)
//    req_dht  : dht11 온습도     -> T=25.0 H=60.0\n    (14글자)
//
//  req_* 는 control_unit 에서 오는 1클럭 펄스다.
//    req_sw / req_wt  : /get 을 받았을 때 현재 화면이 stopwatch / watch 인 경우
//    req_sr / req_dht : /sr04, /dht11 로 시작한 측정이 끝났을 때,
//                       또는 /get 을 받았을 때 현재 화면이 sr04 / dht11 인 경우
//
//  사용하는 기존 모듈: fnd_src_mux (a~d 레인), digit_spliter
// ============================================================================
module ascii_sender #(
    parameter WAIT_CYCLES = 1   // push 후 full이 갱신될 때까지 기다리는 클럭 수 (fifo는 push 다음 클럭에 갱신)
) (
    input        clk,
    input        reset,

    // 요청 (1클럭 펄스, control_unit 에서 옴)
    input        req_sw,
    input        req_wt,
    input        req_sr,
    input        req_dht,

    // stopwatch
    input  [4:0] sw_hour,
    input  [5:0] sw_min,
    input  [5:0] sw_sec,
    input  [6:0] sw_msec,

    // watch
    input  [4:0] wt_hour,
    input  [5:0] wt_min,
    input  [5:0] wt_sec,
    input  [6:0] wt_msec,

    // sr04
    input  [8:0] sr_dist,

    // dht11 (저장된 값)
    input  [7:0] temp_int,
    input  [7:0] temp_dec,
    input  [7:0] hum_int,
    input  [7:0] hum_dec,

    // uart tx fifo
    input        full,
    output reg [7:0] tx_data,
    output reg       push,

    output           busy
);

    localparam [1:0] IDLE = 2'd0, SEND = 2'd1, WAIT = 2'd2;

    reg [1:0] c_state, n_state;
    reg [3:0] idx_reg, idx_next;   // 지금 몇 번째 글자를 보내는지 (0~13)
    reg [2:0] wait_reg, wait_next; // WAIT에서 몇 클럭 쉬었는지

    assign busy = (c_state != IDLE);

    // ------------------------------------------------------------------
    // 1) 요청 -> 소스 선택 (fnd_src_mux의 sel과 같은 의미: 0 sw, 1 wt, 2 sr, 3 dht)
    // ------------------------------------------------------------------
    wire any_req = req_sw | req_wt | req_sr | req_dht;

    reg [1:0] req_sel;

    always @(*) begin
        if      (req_dht) req_sel = 2'd3;
        else if (req_sr)  req_sel = 2'd2;
        else if (req_wt)  req_sel = 2'd1;
        else              req_sel = 2'd0;
    end

    wire [8:0] w_a_src, w_b_src, w_c_src, w_d_src;

    fnd_src_mux U_SRC_MUX (
        .sel     (req_sel),
        .sw_hour (sw_hour), .sw_min(sw_min), .sw_sec(sw_sec), .sw_msec(sw_msec),
        .wt_hour (wt_hour), .wt_min(wt_min), .wt_sec(wt_sec), .wt_msec(wt_msec),
        .sr_dist (sr_dist),
        .temp_int(temp_int), .temp_dec(temp_dec),
        .hum_int (hum_int),  .hum_dec (hum_dec),
        .a(w_a_src), .b(w_b_src), .c(w_c_src), .d(w_d_src)
    );

    // ------------------------------------------------------------------
    // 2) 요청이 들어온 순간 값을 캡처 (전송 중에 값이 바뀌어도 글자가 섞이지 않게)
    //    레인 배치: a b c d
    //      시계  : hour  min   sec   msec
    //      sr04  : -     -     dist  -
    //      dht11 : temp_int temp_dec hum_int hum_dec
    // ------------------------------------------------------------------
    wire capture = (c_state == IDLE) && any_req;

    reg [1:0] sel_reg;
    reg [8:0] a_reg, b_reg, c_reg, d_reg;

    always @(posedge clk, posedge reset) begin
        if (reset) begin
            sel_reg <= 2'd0;
            a_reg   <= 9'd0;
            b_reg   <= 9'd0;
            c_reg   <= 9'd0;
            d_reg   <= 9'd0;
        end else if (capture) begin
            sel_reg <= req_sel;
            a_reg   <= w_a_src;
            b_reg   <= w_b_src;
            c_reg   <= w_c_src;
            d_reg   <= w_d_src;
        end
    end

    // ------------------------------------------------------------------
    // 3) 캡처한 값을 자리 분리 -> ASCII (digit + 0x30)
    // ------------------------------------------------------------------
    wire [3:0] w_a_1, w_a_10;
    wire [3:0] w_b_1, w_b_10;
    wire [3:0] w_c_1, w_c_10, w_c_100;
    wire [3:0] w_d_1, w_d_10;

    digit_spliter #(.BIT_WIDTH(9)) U_DS_A (
        .seg_data(a_reg),
        .digit_1(w_a_1), .digit_10(w_a_10),
        .digit_100()
    );

    digit_spliter #(.BIT_WIDTH(9)) U_DS_B (
        .seg_data(b_reg),
        .digit_1(w_b_1), .digit_10(w_b_10),
        .digit_100()
    );

    digit_spliter #(.BIT_WIDTH(9)) U_DS_C (
        .seg_data(c_reg),
        .digit_1(w_c_1), .digit_10(w_c_10), .digit_100(w_c_100)
    );

    digit_spliter #(.BIT_WIDTH(9)) U_DS_D (
        .seg_data(d_reg),
        .digit_1(w_d_1), .digit_10(w_d_10),
        .digit_100()
    );

    wire [7:0] ch_a_1   = 8'h30 + w_a_1;
    wire [7:0] ch_a_10  = 8'h30 + w_a_10;
    wire [7:0] ch_b_1   = 8'h30 + w_b_1;
    wire [7:0] ch_b_10  = 8'h30 + w_b_10;
    wire [7:0] ch_c_1   = 8'h30 + w_c_1;
    wire [7:0] ch_c_10  = 8'h30 + w_c_10;
    wire [7:0] ch_c_100 = 8'h30 + w_c_100;
    wire [7:0] ch_d_1   = 8'h30 + w_d_1;
    wire [7:0] ch_d_10  = 8'h30 + w_d_10;

    // ------------------------------------------------------------------
    // 4) 문자열 길이
    // ------------------------------------------------------------------
    reg [3:0] msg_len;

    always @(*) begin
        case (sel_reg)
            2'd0:    msg_len = 4'd12;  // HH:MM:SS.mm\n
            2'd1:    msg_len = 4'd12;
            2'd2:    msg_len = 4'd8;   // D=123cm\n
            2'd3:    msg_len = 4'd14;  // T=25.0 H=60.0\n
            default: msg_len = 4'd12;
        endcase
    end

    // ------------------------------------------------------------------
    // 5) idx 번째 글자
    // ------------------------------------------------------------------
    always @(*) begin
        tx_data = 8'h20; // space

        case (sel_reg)
            2'd0, 2'd1: begin  // HH:MM:SS.mm
                case (idx_reg)
                    4'd0:    tx_data = ch_a_10;
                    4'd1:    tx_data = ch_a_1;
                    4'd2:    tx_data = ":";
                    4'd3:    tx_data = ch_b_10;
                    4'd4:    tx_data = ch_b_1;
                    4'd5:    tx_data = ":";
                    4'd6:    tx_data = ch_c_10;
                    4'd7:    tx_data = ch_c_1;
                    4'd8:    tx_data = ".";
                    4'd9:    tx_data = ch_d_10;
                    4'd10:   tx_data = ch_d_1;
                    4'd11:   tx_data = 8'h0A;  // \n
                    default: tx_data = 8'h20;
                endcase
            end

            2'd2: begin  // D=123cm
                case (idx_reg)
                    4'd0:    tx_data = "D";
                    4'd1:    tx_data = "=";
                    4'd2:    tx_data = ch_c_100;
                    4'd3:    tx_data = ch_c_10;
                    4'd4:    tx_data = ch_c_1;
                    4'd5:    tx_data = "c";
                    4'd6:    tx_data = "m";
                    4'd7:    tx_data = 8'h0A;
                    default: tx_data = 8'h20;
                endcase
            end

            2'd3: begin  // T=25.0 H=60.0
                case (idx_reg)
                    4'd0:    tx_data = "T";
                    4'd1:    tx_data = "=";
                    4'd2:    tx_data = ch_a_10;
                    4'd3:    tx_data = ch_a_1;
                    4'd4:    tx_data = ".";
                    4'd5:    tx_data = ch_b_1;
                    4'd6:    tx_data = " ";
                    4'd7:    tx_data = "H";
                    4'd8:    tx_data = "=";
                    4'd9:    tx_data = ch_c_10;
                    4'd10:   tx_data = ch_c_1;
                    4'd11:   tx_data = ".";
                    4'd12:   tx_data = ch_d_1;
                    4'd13:   tx_data = 8'h0A;
                    default: tx_data = 8'h20;
                endcase
            end

            default: tx_data = 8'h20;
        endcase
    end

    // ------------------------------------------------------------------
    // 6) FSM : IDLE -> SEND -> WAIT -> (남았으면 SEND, 끝났으면 IDLE)
    // ------------------------------------------------------------------
    always @(posedge clk or posedge reset) begin
        if (reset) begin
            c_state  <= IDLE;
            idx_reg  <= 4'd0;
            wait_reg <= 3'd0;
        end else begin
            c_state  <= n_state;
            idx_reg  <= idx_next;
            wait_reg <= wait_next;
        end
    end

    always @(*) begin
        n_state   = c_state;
        idx_next  = idx_reg;
        wait_next = 3'd0;
        push      = 1'b0;

        case (c_state)
            IDLE: begin
                idx_next = 4'd0;
                if (any_req) n_state = SEND;
            end

            SEND: begin
                if (!full) begin          // fifo에 자리가 있을 때만
                    push     = 1'b1;      // 1클럭 펄스
                    idx_next = idx_reg + 1;
                    n_state  = WAIT;
                end
            end

            WAIT: begin                   // push 직후 full이 갱신될 시간 확보
                if (wait_reg == WAIT_CYCLES - 1) begin
                    if (idx_reg == msg_len) n_state = IDLE;
                    else                    n_state = SEND;
                end else begin
                    wait_next = wait_reg + 1;
                end
            end

            default: n_state = IDLE;
        endcase
    end

endmodule