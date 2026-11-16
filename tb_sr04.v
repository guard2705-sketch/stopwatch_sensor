`timescale 1ns / 1ps

// SR04_controller 테스트
//   tb가 버튼(start)과 초음파 센서(echo) 역할을 한다.
//   distance = echo 폭(us) / 58
//     echo 600us  -> 10cm
//     echo 5830us -> 100cm
module tb_sr04;

    reg clk = 0;
    reg reset = 1;
    always #5 clk = ~clk;  // 100MHz

    reg  start = 0;
    reg  echo  = 0;
    wire trigger;
    wire done;
    wire [8:0] distance;

    SR04_controller DUT (
        .clk(clk), .reset(reset),
        .start(start), .echo(echo),
        .trigger(trigger), .done(done), .distance(distance)
    );

    initial begin
        #100 reset = 0;
        #100;

        // ---- 첫 번째 측정 : echo 600us ----
        start = 1;  #20;  start = 0;     // start 펄스
        #300_000;                        // 센서가 초음파를 쏘는 시간 (300us)
        echo = 1;   #600_000;   echo = 0;    // echo 600us
        #10_000;
        $display("echo 600us  -> distance = %0d (10이면 정상)", distance);

        // ---- 두 번째 측정 : echo 5830us ----
        #100_000;
        start = 1;  #20;  start = 0;
        #300_000;
        echo = 1;   #5_830_000; echo = 0;
        #10_000;
        $display("echo 5830us -> distance = %0d (100이면 정상)", distance);

        $finish;
    end

endmodule