
module fnd_controller (

    input clk,
    input reset,
    input [1:0] sel,
    input display_mode,
    input blink_onoff,
    input [8:0] a,
    input [8:0] b,
    input [8:0] c,
    input [8:0] d,

    output [3:0] fnd_com,
    output [7:0] fnd_data
);

    wire       w_1khz;
    wire [2:0] w_digit_sel;
    wire       w_tick_100hz;

    clk_div U_CLK_DIV (
        .clk   (clk),
        .reset (reset),
        .o_1khz(w_1khz)
    );

    counter_8 U_COUNTER_8 (
        .clk      (w_1khz),
        .reset    (reset),
        .digit_sel(w_digit_sel)
    );

    decoder_2x4 U_DECODER_2x4 (
        .digit_sel(w_digit_sel[1:0]),
        .fnd_com  (fnd_com)
    );

    tick_gen_100hz U_GEN_100HZ (
        .clk   (clk),
        .reset (reset),
        .o_tick(w_tick_100hz)
    );

    wire [3:0] w_a_1, w_a_10;
    wire [3:0] w_b_1, w_b_10;
    wire [3:0] w_c_1, w_c_10, w_c_100;
    wire [3:0] w_d_1, w_d_10;


    digit_spliter #(
        .BIT_WIDTH(9)
    ) U_DS_A (
        .seg_data (a),
        .digit_1  (w_a_1),
        .digit_10 (w_a_10),
        .digit_100()
    );

    digit_spliter #(
        .BIT_WIDTH(9)
    ) U_DS_B (
        .seg_data (b),
        .digit_1  (w_b_1),
        .digit_10 (w_b_10),
        .digit_100()
    );

    digit_spliter #(
        .BIT_WIDTH(9)
    ) U_DS_C (
        .seg_data (c),
        .digit_1  (w_c_1),
        .digit_10 (w_c_10),
        .digit_100(w_c_100)
    );

    digit_spliter #(
        .BIT_WIDTH(9)
    ) U_DS_D (
        .seg_data (d),
        .digit_1  (w_d_1),
        .digit_10 (w_d_10),
        .digit_100()
    );

    wire [3:0] w_msec_sec, w_min_hour;
    wire [3:0] w_msec_sec_bcd, w_min_hour_bcd;
    wire [3:0] w_time_bcd;
    wire       w_dot_onoff;

    comparator_dot #(
        .MSEC_WIDTH(7)
    ) U_COMP_DOT (
        .msec     (d[6:0]),
        .dot_onoff(w_dot_onoff)
    );

    mux_8x1 U_MUX_8X1_MSEC_SEC (
        .sel(w_digit_sel),
        .in0(w_d_1),     // msec 1
        .in1(w_d_10),    // msec 10
        .in2(w_c_1),     // sec 1
        .in3(w_c_10),    // sec 10
        .in4(4'hf),
        .in5(4'hf),
        .in6({3'b111, w_dot_onoff}),
        .in7(4'hf),
        .mux_out(w_msec_sec)
    );

    mux_8x1 U_MUX_8X1_MIN_HOUR (
        .sel(w_digit_sel),
        .in0(w_b_1),     // min 1
        .in1(w_b_10),    // min 10
        .in2(w_a_1),     // hour 1
        .in3(w_a_10),    // hour 10
        .in4(4'hf),
        .in5(4'hf),
        .in6({3'b111, w_dot_onoff}),
        .in7(4'hf),
        .mux_out(w_min_hour)
    );

    //blink는 stopwatch 선택 시 동작
    wire w_blink_bin = blink_onoff & (sel == 2'd0);

    blink U_BLINK_SEC_MSEC (
        .bin       (w_blink_bin),
        .clk_100hz (w_tick_100hz),
        .reset     (reset),
        .data      (w_msec_sec),
        .blink_data(w_msec_sec_bcd)
    );

    blink U_BLINK_HOUR_MIN (
        .bin       (w_blink_bin),
        .clk_100hz (w_tick_100hz),
        .reset     (reset),
        .data      (w_min_hour),
        .blink_data(w_min_hour_bcd)
    );

    mux_2x1 U_MUX_2X1_TIME (
        .sel    (display_mode),
        .in0    (w_msec_sec_bcd),
        .in1    (w_min_hour_bcd),
        .mux_out(w_time_bcd)
    );

    // 2) sr04 : c= dist (3자리)

    wire [3:0] w_sr_bcd;

    mux_8x1 U_MUX_8X1_SR04 (
        .sel(w_digit_sel),
        .in0(w_c_1),
        .in1(w_c_10),
        .in2(w_c_100),
        .in3(4'hf),
        .in4(4'hf),
        .in5(4'hf),
        .in6(4'hf),
        .in7(4'hf),
        .mux_out(w_sr_bcd)
    );

    // 3) dht11 : a=temp_int, b=temp_dec, c=hum_int, d=hum_dec
    wire [3:0] w_temp_bcd, w_hum_bcd;
    wire [3:0] w_dht_bcd;

    mux_8x1 U_MUX_8X1_DHT_TEMP (
        .sel(w_digit_sel),
        .in0(w_b_1),  // temp_dec:1
        .in1(w_a_1),  // temp_int:1
        .in2(w_a_10), // temp_int:10
        .in3(4'hf),
        .in4(4'hf),
        .in5(4'he),
        .in6(4'hf),
        .in7(4'hf),
        .mux_out(w_temp_bcd)
    );

    mux_8x1 U_MUX_8X1_DHT_HUM (
        .sel(w_digit_sel),
        .in0(w_d_1),  // hum_dec:1
        .in1(w_d_10), // hum_dec:10
        .in2(w_c_1),  // hum_int:1
        .in3(w_c_10), // hum_int:10
        .in4(4'hf),
        .in5(4'hf),
        .in6(4'he),
        .in7(4'hf),
        .mux_out(w_hum_bcd)
    );

    mux_2x1 U_MUX_2X1_DHT (
        .sel    (display_mode),
        .in0    (w_temp_bcd),
        .in1    (w_hum_bcd),
        .mux_out(w_dht_bcd)
    );

    wire [3:0] w_ext_bcd;
    wire [3:0] bcd;
 
    mux_2x1 U_MUX_2X1_EXT (
        .sel    (sel[0]),
        .in0    (w_sr_bcd),
        .in1    (w_dht_bcd),
        .mux_out(w_ext_bcd)
    );

    mux_2x1 U_MUX_2X1_FINAL (
        .sel    (sel[1]),
        .in0    (w_time_bcd),
        .in1    (w_ext_bcd),
        .mux_out(bcd)
    );
    
    // sel[1:0] 00:stopwatch, 01:watch, 10:sr04, 11:dht11

    bcd U_BCD (
        .bcd_in (bcd),
        .bcd_out(fnd_data)
    );


endmodule

// 100Mhz ->1khz
module clk_div (
    input  clk,
    input  reset,
    output o_1khz
);
    reg [15:0] counter_reg;
    reg clk_reg;
    // sequential logic
    always @(posedge clk, posedge reset) begin
        if (reset) begin
            counter_reg <= 1'b0;
            clk_reg <= 1'b0;
        end else begin
            counter_reg <= counter_reg + 16'd1;
            if (counter_reg == 16'd49999) begin
                counter_reg <= 16'd0;
                clk_reg     <= ~clk_reg;
            end
        end
    end
    assign o_1khz = clk_reg;

endmodule

module counter_8 (
    input clk,
    input reset,
    output [2:0] digit_sel
);

    reg [2:0] counter_reg;
    assign digit_sel = counter_reg;

    always @(posedge clk, posedge reset) begin
        if (reset) counter_reg <= 3'd0;
        else counter_reg <= counter_reg + 3'd1;
    end

endmodule

module decoder_2x4 (
    input [1:0] digit_sel,
    output reg [3:0] fnd_com
);
    always @(digit_sel) begin
        case (digit_sel)
            2'b00: fnd_com = 4'b1110;
            2'b01: fnd_com = 4'b1101;
            2'b10: fnd_com = 4'b1011;
            2'b11: fnd_com = 4'b0111;
            default fnd_com = 4'b1111;
        endcase
    end
endmodule

module tick_gen_100hz (
    input clk,
    input reset,
    output reg o_tick
);


    parameter F_COUNT = 1_000_000;
    reg [$clog2(F_COUNT) - 1:0] counter_reg;

    always @(posedge clk, posedge reset) begin
        if (reset) begin
            counter_reg <= 0;
            o_tick <= 1'b0;
        end else begin
            counter_reg <= counter_reg + 1;
            if (counter_reg == F_COUNT - 1) begin
                counter_reg <= 0;
                o_tick <= 1'b1;
            end else o_tick <= 1'b0;
        end

    end

endmodule


module digit_spliter #(
    BIT_WIDTH = 9
) (
    input [BIT_WIDTH-1:0] seg_data,
    output [3:0]digit_1,
    output [3:0] digit_10,
    output [3:0] digit_100
);

    assign digit_1   = seg_data % 10;
    assign digit_10  = ((seg_data) / 10) % 10;
    assign digit_100 = ((seg_data) / 100) % 10;
endmodule



module comparator_dot #(
    parameter MSEC_WIDTH = 7
) (
    input [MSEC_WIDTH-1:0] msec,
    output dot_onoff
);

    assign dot_onoff = (msec < 50);
endmodule

module mux_8x1 (
    input [2:0] sel,
    input [3:0] in0,
    input [3:0] in1,
    input [3:0] in2,
    input [3:0] in3,
    input [3:0] in4,
    input [3:0] in5,
    input [3:0] in6,
    input [3:0] in7,

    output reg [3:0] mux_out
);
    always @(*) begin
        case (sel)
            3'b000: mux_out = in0;
            3'b001: mux_out = in1;
            3'b010: mux_out = in2;
            3'b011: mux_out = in3;
            3'b100: mux_out = in4;
            3'b101: mux_out = in5;
            3'b110: mux_out = in6;
            3'b111: mux_out = in7;
        endcase
    end
endmodule

module blink (
    input bin,  // light 
    input clk_100hz,
    input reset,
    input [3:0] data,
    output [3:0] blink_data
);
    reg [5:0] count_reg;
    reg light_check;  // on/off state 


    always @(posedge clk_100hz, posedge reset) begin
        if (reset) begin
            count_reg   <= 6'b0;
            light_check <= 1'b0;
        end else if (bin == 1'b1) begin
            if (count_reg <= 6'd49) count_reg <= count_reg + 1;
            else begin  //bin==1&& count_reg==50  0.01*50->0.5s on, 0.5s off
                count_reg   <= 6'b0;
                light_check <= ~light_check;  //light_check 1
            end
        end else begin  //bin==1'b0
            count_reg   <= 6'b0;
            light_check <= 1'b0;
        end
    end

    assign blink_data = (bin && light_check) ? 4'hf : data;

endmodule

module mux_2x1 (
    input sel,
    input [3:0] in0,
    input [3:0] in1,
    output [3:0] mux_out
);

    assign mux_out = (sel) ? in1 : in0;

endmodule

module bcd(
    input      [3:0] bcd_in,
    output reg [7:0] bcd_out
);

    always @(bcd_in) begin // 항상 @() 내부에 있는 것을 감시하여 변화가 있으면 begin ~ end 내부를 실행하라
        case (bcd_in)
            4'b0000: bcd_out = 8'hc0;
            4'b0001: bcd_out = 8'hf9;
            4'b0010: bcd_out = 8'ha4;
            4'b0011: bcd_out = 8'hb0;
            4'b0100: bcd_out = 8'h99;
            4'b0101: bcd_out = 8'h92;
            4'b0110: bcd_out = 8'h82;
            4'b0111: bcd_out = 8'hf8;
            4'b1000: bcd_out = 8'h80;
            4'b1001: bcd_out = 8'h90;
            4'b1010: bcd_out = 8'h88;
            4'b1011: bcd_out = 8'h83;
            4'b1100: bcd_out = 8'hc6;
            4'b1101: bcd_out = 8'ha1;
            4'b1110: bcd_out = 8'h7f;  // dot display on
            4'b1111: bcd_out = 8'hff;  // dot display off
        endcase
    end

endmodule