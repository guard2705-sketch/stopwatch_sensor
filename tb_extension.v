`timescale 1ns / 1ps

module tb_extension();


    reg  [4:0] a = 5'd23;
    wire [8:0] b = a;

    reg  [8:0] x = 9'd300;
    wire [5:0] y = x;

    reg  [3:0] c = 4'd9, d = 4'd8;
    wire [4:0] s = c + d;
    wire [3:0] t = c + d;

    initial begin
        #1;
        $display("b = %b (%0d)", b, b);   // 000010111 (23)
        $display("y = %b (%0d)", y, y);   // 101100 (44)
        $display("s = %0d, t = %0d", s, t); // 17, 1
    end
endmodule
