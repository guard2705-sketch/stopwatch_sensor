`timescale 1ns / 1ps

// top_system 연결 테스트 (실제 9600bps)
//   tb가 PC 역할을 한다. 센서는 건드리지 않는다.
//
//   시나리오
//     1) "/get" 전송 -> tx로 "00:00:00.00" 이 온다 (stopwatch 정지 상태)
//     2) "/run" 전송 -> 20ms 기다리면 stopwatch가 돌아서 값이 바뀐다
//     3) "/get" 전송 -> 0이 아닌 시간이 온다
//     4) sw를 바꾸면 led가 따라 바뀐다
//
//   시뮬레이션 시간이 길다(약 70ms). Vivado에서 run time을 100ms 이상으로 설정할 것.
module tb_top_system;

    reg clk = 0;
    reg reset = 1;
    always #5 clk = ~clk;  // 100MHz

    reg  [4:0] sw = 5'b00000;
    reg        rx = 1;
    wire       tx;
    wire [3:0] fnd_com;
    wire [7:0] fnd_data;
    wire [4:0] led;
    wire       trigger;

    // 센서 핀은 건드리지 않는다 (echo = 0, dht11_io는 풀업)
    wire dht11_io;
    pullup (dht11_io);

    top_system DUT (
        .clk(clk), .reset(reset),
        .sw(sw),
        .btn_L(1'b0), .btn_R(1'b0), .btn_U(1'b0), .btn_D(1'b0), .btn_C(1'b0),
        .echo(1'b0), .trigger(trigger),
        .dht11_io(dht11_io),
        .rx(rx), .tx(tx),
        .fnd_com(fnd_com), .fnd_data(fnd_data),
        .led(led)
    );

    // 9600bps 한 비트 시간 (ns)
    parameter BIT_TIME = 104167;

    // PC가 한 글자 보내기
    task send_byte(input [7:0] b);
        integer k;
        begin
            rx = 0;                    // 시작 비트
            #(BIT_TIME);
            for (k = 0; k < 8; k = k + 1) begin
                rx = b[k];             // 데이터 비트 (LSB부터)
                #(BIT_TIME);
            end
            rx = 1;                    // 정지 비트
            #(BIT_TIME);
        end
    endtask

    // PC가 tx로 받은 글자를 출력 (시작 비트를 잡고 비트 가운데에서 읽는다)
    reg [7:0] rx_char;
    integer   k;

    always @(negedge tx) begin
        #(BIT_TIME / 2);               // 시작 비트 가운데
        for (k = 0; k < 8; k = k + 1) begin
            #(BIT_TIME);
            rx_char[k] = tx;           // 데이터 비트 가운데
        end
        #(BIT_TIME);                   // 정지 비트 가운데
        $write("%c", rx_char);         // LF(0x0A)가 오면 줄이 바뀐다
    end

    initial begin
        #200 reset = 0;
        #(BIT_TIME * 2);

        // 1) /get -> 00:00:00.00 이 와야 함
        $display("[1] /get (stopwatch 정지)");
        send_byte("/"); send_byte("g"); send_byte("e"); send_byte("t"); send_byte(8'h0A);
        #15_000_000;                   // 응답이 올 때까지 기다림 (12글자 약 12.5ms)

        // 2) /run -> stopwatch 시작
        $display("[2] /run 후 20ms 기다림");
        send_byte("/"); send_byte("r"); send_byte("u"); send_byte("n"); send_byte(8'h0A);
        #20_000_000;
        $display("   내부 w_sw_sec = %0d, w_sw_msec = %0d (0이 아니면 정상)",
                 DUT.w_sw_sec, DUT.w_sw_msec);

        // 3) /get -> 0이 아닌 시간
        $display("[3] /get (stopwatch 동작 중)");
        send_byte("/"); send_byte("g"); send_byte("e"); send_byte("t"); send_byte(8'h0A);
        #15_000_000;

        // 4) led 확인
        sw = 5'b10101;
        #100;
        $display("[4] sw = 10101 -> led = %b (같으면 정상)", led);

        $finish;
    end

endmodule