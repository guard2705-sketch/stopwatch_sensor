`timescale 1ns / 1ps

// ============================================================================
// top_system
//
//   버튼/스위치 --> btn_debounce --> control_unit --> stopwatch_datapath ┐
//   PC(rx) -> uart_rx -> FIFO_RX -> ascii_decoder ->(명령)-> control_unit ├-> fnd_src_mux -> fnd_controller
//                                                         -> watch_datapath ┘
//                                  control_unit(sr04, dht11 포함) -> req_* -> ascii_sender
//   PC(tx) <- uart_tx <- FIFO_TX <- ascii_sender
//
//   sw[0] display_mode   sw[1] watch   sw[2] sr04   sw[3] dht11   sw[4] save
//   (전부 꺼지면 stopwatch)
//   led[4:0] = sw[4:0]
// ============================================================================
module top_system (
    input        clk,
    input        reset,
    input  [4:0] sw,

    input        btn_L,
    input        btn_R,
    input        btn_U,
    input        btn_D,
    input        btn_C,

    // sr04
    input        echo,
    output       trigger,

    // dht11
    inout        dht11_io,

    // uart
    input        rx,
    output       tx,

    // fnd
    output [3:0] fnd_com,
    output [7:0] fnd_data,

    // led : sw[i] 를 켜면 led[i] 가 켜진다
    output [4:0] led
);

    // ------------------------------------------------------------------
    // 0) 여러 블록이 같이 쓰는 wire 선언
    //    (Verilog는 선언 전에 쓰면 1비트 wire로 잘못 만들어지므로 모두 위에서 선언)
    // ------------------------------------------------------------------
    // 모드 / 제어
    wire [1:0] w_sel;
    wire       w_display_mode, w_save;

    // stopwatch 값
    wire [4:0] w_sw_hour;
    wire [5:0] w_sw_min, w_sw_sec;
    wire [6:0] w_sw_msec;
    wire       w_blink_onoff;

    // watch 값
    wire [4:0] w_wt_hour;
    wire [5:0] w_wt_min, w_wt_sec;
    wire [6:0] w_wt_msec;

    // 센서 값
    wire [8:0] w_sr_dist;
    wire [7:0] w_temp_int, w_temp_dec, w_hum_int, w_hum_dec;

    // ------------------------------------------------------------------
    // 1) 버튼 디바운스
    // ------------------------------------------------------------------
    wire w_btn_L, w_btn_R, w_btn_U, w_btn_D, w_btn_C;

    btn_debounce U_BD_L (.clk(clk), .reset(reset), .i_btn(btn_L), .o_btn(w_btn_L));
    btn_debounce U_BD_R (.clk(clk), .reset(reset), .i_btn(btn_R), .o_btn(w_btn_R));
    btn_debounce U_BD_U (.clk(clk), .reset(reset), .i_btn(btn_U), .o_btn(w_btn_U));
    btn_debounce U_BD_D (.clk(clk), .reset(reset), .i_btn(btn_D), .o_btn(w_btn_D));
    btn_debounce U_BD_C (.clk(clk), .reset(reset), .i_btn(btn_C), .o_btn(w_btn_C));

    // ------------------------------------------------------------------
    // 2) UART + FIFO + ASCII decoder / sender
    // ------------------------------------------------------------------
    // uart_fifo <-> ascii_decoder (RX 경로)
    wire [7:0] w_rx_rdata;
    wire       w_rx_empty, w_dec_pop;

    // 디코더 명령
    wire w_com_run, w_com_clear, w_com_mode, w_com_opt, w_com_lm, w_com_rm;
    wire w_com_inc, w_com_dec, w_com_dht11, w_com_sr04, w_com_get;

    // ascii_sender <-> uart_fifo (TX 경로)
    wire [7:0] w_snd_data;
    wire       w_snd_push, w_tx_full;

    // sender 요청 (control_unit -> ascii_sender, 모두 1클럭 펄스)
    //   w_req_sw / w_req_wt   : /get 을 받았을 때 현재 화면이 stopwatch / watch
    //   w_req_sr / w_req_dht  : /sr04, /dht11 로 시작한 측정이 끝났을 때
    //                           또는 /get 을 받았을 때 현재 화면이 sr04 / dht11
    wire w_req_sw, w_req_wt, w_req_sr, w_req_dht;

    uart_fifo U_UART_FIFO (
        .clk(clk), .reset(reset),
        .rx(rx), .tx(tx),
        // RX FIFO -> ascii_decoder
        .pop(w_dec_pop), .rx_data(w_rx_rdata), .empty(w_rx_empty),
        // ascii_sender -> TX FIFO
        .push(w_snd_push), .tx_data(w_snd_data), .full(w_tx_full)
    );

    ascii_decoder U_ASCII_DECODER (
        .clk(clk), .reset(reset),
        .empty(w_rx_empty), .rx_data(w_rx_rdata), .pop(w_dec_pop),
        .o_com_run(w_com_run),     .o_com_clear(w_com_clear),
        .o_com_mode(w_com_mode),   .o_com_opt(w_com_opt),
        .o_com_lm(w_com_lm),       .o_com_rm(w_com_rm),
        .o_com_inc(w_com_inc),     .o_com_dec(w_com_dec),
        .o_com_dht11(w_com_dht11), .o_com_sr04(w_com_sr04),
        .o_com_get(w_com_get)
    );

    // ascii_sender (요청 펄스가 오면 해당 소스의 값을 PC로 전송)
    ascii_sender #(.WAIT_CYCLES(1)) U_ASCII_SENDER (
        .clk(clk), .reset(reset),

        .req_sw(w_req_sw), .req_wt(w_req_wt),
        .req_sr(w_req_sr), .req_dht(w_req_dht),

        .sw_hour(w_sw_hour), .sw_min(w_sw_min),
        .sw_sec(w_sw_sec), .sw_msec(w_sw_msec),

        .wt_hour(w_wt_hour), .wt_min(w_wt_min),
        .wt_sec(w_wt_sec), .wt_msec(w_wt_msec),

        .sr_dist(w_sr_dist),

        .temp_int(w_temp_int), .temp_dec(w_temp_dec),
        .hum_int(w_hum_int),   .hum_dec(w_hum_dec),

        .full(w_tx_full), .tx_data(w_snd_data), .push(w_snd_push),
        .busy()
    );

    // (TX FIFO / uart_tx 는 uart_fifo 안에 있음)

    // ------------------------------------------------------------------
    // 3) control unit (stopwatch/watch control, sr04, dht11 포함)
    // ------------------------------------------------------------------
    wire       w_sw_run_stop, w_sw_clear, w_sw_mode, w_sw_min_inc;
    wire       w_wt_hour_inc_en, w_wt_hour_dec_en, w_wt_min_inc_en, w_wt_min_dec_en;

    control_unit U_CONTROL_UNIT (
        .clk(clk), .reset(reset),
        .sw(sw),

        .d_btn_L(w_btn_L), .d_btn_R(w_btn_R), .d_btn_U(w_btn_U),
        .d_btn_D(w_btn_D), .d_btn_C(w_btn_C),

        .com_run(w_com_run),     .com_clear(w_com_clear),
        .com_mode(w_com_mode),   .com_opt(w_com_opt),
        .com_lm(w_com_lm),       .com_rm(w_com_rm),
        .com_inc(w_com_inc),     .com_dec(w_com_dec),
        .com_dht11(w_com_dht11), .com_sr04(w_com_sr04), .com_get(w_com_get),

        .sel(w_sel), .display_mode(w_display_mode), .save(w_save),

        .sw_run_stop(w_sw_run_stop), .sw_clear(w_sw_clear),
        .sw_mode(w_sw_mode),         .sw_min_inc(w_sw_min_inc),

        .wt_hour_inc_en(w_wt_hour_inc_en), .wt_hour_dec_en(w_wt_hour_dec_en),
        .wt_min_inc_en(w_wt_min_inc_en),   .wt_min_dec_en(w_wt_min_dec_en),

        .echo(echo), .trigger(trigger), .sr_dist(w_sr_dist), .req_sr(w_req_sr),
        .req_sw(w_req_sw), .req_wt(w_req_wt),

        .dht11_io(dht11_io),
        .temp_int(w_temp_int), .temp_dec(w_temp_dec),
        .hum_int(w_hum_int),   .hum_dec(w_hum_dec),
        .req_dht(w_req_dht)
    );

    // ------------------------------------------------------------------
    // 4) datapath
    // ------------------------------------------------------------------
    stopwatch_datapath U_STOPWATCH_DATAPATH (
        .clk(clk), .reset(reset),
        .run_stop(w_sw_run_stop), .clear(w_sw_clear),
        .mode(w_sw_mode), .min_inc(w_sw_min_inc),
        .save(w_save),
        .msec(w_sw_msec), .sec(w_sw_sec), .min(w_sw_min), .hour(w_sw_hour),
        .blink_onoff(w_blink_onoff)
    );

    watch_datapath #(
        .MSEC_WIDTH(7), .SEC_WIDTH(6), .MIN_WIDTH(6), .HOUR_WIDTH(5)
    ) U_WATCH_DATAPATH (
        .clk(clk), .reset(reset),
        .hour_inc_en(w_wt_hour_inc_en), .hour_dec_en(w_wt_hour_dec_en),
        .min_inc_en(w_wt_min_inc_en),   .min_dec_en(w_wt_min_dec_en),
        .msec(w_wt_msec), .sec(w_wt_sec), .min(w_wt_min), .hour(w_wt_hour)
    );

    // ------------------------------------------------------------------
    // 5) 화면: 소스 선택 mux -> fnd_controller
    // ------------------------------------------------------------------
    wire [8:0] w_a, w_b, w_c, w_d;

    fnd_src_mux U_FND_SRC_MUX (
        .sel(w_sel),

        .sw_hour(w_sw_hour), .sw_min(w_sw_min),
        .sw_sec(w_sw_sec), .sw_msec(w_sw_msec),

        .wt_hour(w_wt_hour), .wt_min(w_wt_min),
        .wt_sec(w_wt_sec), .wt_msec(w_wt_msec),

        .sr_dist(w_sr_dist),

        .temp_int(w_temp_int), .temp_dec(w_temp_dec),
        .hum_int(w_hum_int),   .hum_dec(w_hum_dec),

        .a(w_a), .b(w_b), .c(w_c), .d(w_d)
    );

    fnd_controller U_FND_CONTROLLER (
        .clk(clk), .reset(reset),
        .sel(w_sel), .display_mode(w_display_mode),
        .blink_onoff(w_blink_onoff),
        .a(w_a), .b(w_b), .c(w_c), .d(w_d),
        .fnd_com(fnd_com), .fnd_data(fnd_data)
    );

    // ------------------------------------------------------------------
    // 6) led : 스위치 상태를 그대로 표시
    // ------------------------------------------------------------------
    assign led = sw;

endmodule