`timescale 1ns / 1ps

// ascii_sender 테스트
//   req_*를 1클럭 펄스로 주면 sender가 문자열을 FIFO에 한 글자씩 넣는다.
//   FIFO는 4칸이라 꽉 차는데, 느린 소비자(50클럭마다 1글자 꺼냄)가
//   uart_tx 역할을 하며 꺼낸 글자를 콘솔에 출력한다.
//
//   기대 출력
//     12:30:05.07
//     08:05:09.50
//     D=123cm
//     T=28.1 H=60.0
module tb_ascii_sender;

    reg clk = 0;
    reg reset = 1;
    always #5 clk = ~clk;  // 100MHz

    // 요청 신호
    reg req_sw = 0, req_wt = 0, req_sr = 0, req_dht = 0;

    wire       push, busy, full, empty;
    wire [7:0] tx_data, rdata;
    reg        pop = 0;

    ascii_sender DUT (
        .clk(clk), .reset(reset),
        .req_sw(req_sw), .req_wt(req_wt), .req_sr(req_sr), .req_dht(req_dht),

        // stopwatch : 12시 30분 05초 07
        .sw_hour(5'd12), .sw_min(6'd30), .sw_sec(6'd5), .sw_msec(7'd7),
        // watch : 08시 05분 09초 50
        .wt_hour(5'd8),  .wt_min(6'd5),  .wt_sec(6'd9), .wt_msec(7'd50),
        // sr04 : 123cm
        .sr_dist(9'd123),
        // dht11 : 온도 28.1, 습도 60.0
        .temp_int(8'd28), .temp_dec(8'd1), .hum_int(8'd60), .hum_dec(8'd0),

        .full(full), .tx_data(tx_data), .push(push), .busy(busy)
    );

    fifo U_FIFO (
        .clk(clk), .reset(reset),
        .push(push), .pop(pop),
        .wdata(tx_data), .rdata(rdata),
        .full(full), .empty(empty)
    );

    // 느린 소비자 : 50클럭마다 한 글자 꺼내서 출력
    integer cnt = 0;

    always @(posedge clk) begin
        pop <= 0;
        cnt <= cnt + 1;
        if (!empty && cnt >= 50) begin
            $write("%c", rdata);   // LF(0x0A)가 오면 줄이 바뀐다
            pop <= 1;
            cnt <= 0;
        end
    end

    initial begin
        #52 reset = 0;
        #100;

        // 1) stopwatch 요청
        @(negedge clk) req_sw = 1;
        @(negedge clk) req_sw = 0;
        #20000;

        // 2) watch 요청
        @(negedge clk) req_wt = 1;
        @(negedge clk) req_wt = 0;
        #20000;

        // 3) sr04 요청
        @(negedge clk) req_sr = 1;
        @(negedge clk) req_sr = 0;
        #20000;

        // 4) dht11 요청
        @(negedge clk) req_dht = 1;
        @(negedge clk) req_dht = 0;
        #20000;

        $finish;
    end

endmodule