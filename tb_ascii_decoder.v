`timescale 1ns / 1ps

// ascii_decoder 테스트
//   FIFO에서 글자가 나오는 것처럼 rx_data와 empty를 직접 넣는다.
//   글자 하나 = (empty=0, rx_data=글자)를 1클럭 동안 유지
//   마지막에 LF(0x0A)를 보내면 명령을 해석한다.
module tb_ascii_decoder;

    reg clk = 0;
    reg reset = 1;
    always #5 clk = ~clk;  // 100MHz

    reg        empty = 1;
    reg  [7:0] rx_data = 0;
    wire       pop;

    wire o_com_run, o_com_clear, o_com_mode, o_com_opt;
    wire o_com_lm, o_com_rm, o_com_inc, o_com_dec;
    wire o_com_dht11, o_com_sr04, o_com_get;

    ascii_decoder DUT (
        .clk(clk), .reset(reset),
        .empty(empty), .rx_data(rx_data), .pop(pop),
        .o_com_run(o_com_run),     .o_com_clear(o_com_clear),
        .o_com_mode(o_com_mode),   .o_com_opt(o_com_opt),
        .o_com_lm(o_com_lm),       .o_com_rm(o_com_rm),
        .o_com_inc(o_com_inc),     .o_com_dec(o_com_dec),
        .o_com_dht11(o_com_dht11), .o_com_sr04(o_com_sr04),
        .o_com_get(o_com_get)
    );

    // 펄스가 몇 번 나왔는지 센다 (1클럭 펄스면 1번)
    integer run_cnt = 0;
    integer get_cnt = 0;
    integer any_cnt = 0;   // 어떤 명령이든

    always @(posedge clk) begin
        if (o_com_run) run_cnt <= run_cnt + 1;
        if (o_com_get) get_cnt <= get_cnt + 1;
        if (o_com_run | o_com_clear | o_com_mode | o_com_opt | o_com_lm | o_com_rm |
            o_com_inc | o_com_dec | o_com_dht11 | o_com_sr04 | o_com_get)
            any_cnt <= any_cnt + 1;
    end

    // 글자 하나 보내기 (FIFO에서 한 글자 나오는 것)
    task 
        send_char(input [7:0] c);
        begin
            @(negedge clk);
            rx_data = c;
            empty = 0;       // 글자 있음
            @(negedge clk);
            empty = 1;       // 비움
        end
    endtask

    initial begin
        #100 reset = 0;
        #50;

        // "/run" + LF
        send_char("/"); send_char("r"); send_char("u"); send_char("n"); send_char(8'h0A);
        #100;
        $display("/run  -> run_cnt = %0d (1이면 정상)", run_cnt);

        // "/get" + LF
        send_char("/"); send_char("g"); send_char("e"); send_char("t"); send_char(8'h0A);
        #100;
        $display("/get  -> get_cnt = %0d (1이면 정상)", get_cnt);

        // "/GET" + LF (대문자)
        send_char("/"); send_char("G"); send_char("E"); send_char("T"); send_char(8'h0A);
        #100;
        $display("/GET  -> get_cnt = %0d (2이면 정상)", get_cnt);

        // "/abc" + LF (없는 명령 -> 펄스가 늘면 안 됨)
        send_char("/"); send_char("a"); send_char("b"); send_char("c"); send_char(8'h0A);
        #100;
        $display("/abc  -> any_cnt = %0d (3이면 정상, 늘지 않아야 함)", any_cnt);

        $finish;
    end

endmodule