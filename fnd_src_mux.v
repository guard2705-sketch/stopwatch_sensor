
module fnd_src_mux (
    input [1:0] sel,

    // stopwatch 
    input [4:0] sw_hour,
    input [5:0] sw_min,
    input [5:0] sw_sec,
    input [6:0] sw_msec,

    // watch
    input [4:0] wt_hour,
    input [5:0] wt_min,
    input [5:0] wt_sec,
    input [6:0] wt_msec,

    // sr04 
    input [8:0] sr_dist,

    // dht11 
    input [7:0] temp_int,
    input [7:0] temp_dec,
    input [7:0] hum_int,
    input [7:0] hum_dec,

    output [8:0] a,
    output [8:0] b,
    output [8:0] c,
    output [8:0] d
);

    wire [8:0] sw_a = sw_hour;
    wire [8:0] sw_b = sw_min;
    wire [8:0] sw_c = sw_sec;
    wire [8:0] sw_d = sw_msec;

    wire [8:0] wt_a = wt_hour;
    wire [8:0] wt_b = wt_min;
    wire [8:0] wt_c = wt_sec;
    wire [8:0] wt_d = wt_msec;

    wire [8:0] dht_a = temp_int;
    wire [8:0] dht_b = temp_dec;
    wire [8:0] dht_c = hum_int;
    wire [8:0] dht_d = hum_dec;



    // hour/temp_int
    mux_src_4x1_bit #(.BIT_WIDTH(
        9
    )) U_MUX_A (
        .sel(sel),
        .in0(sw_a),
        .in1(wt_a),
        .in2(9'd0),
        .in3(dht_a),
        .mux_out(a)
    );

     // min/temp_dec
    mux_src_4x1_bit #(.BIT_WIDTH(
        9
    )) U_MUX_B (
        .sel(sel),
        .in0(sw_b),
        .in1(wt_b),
        .in2(9'b0),
        .in3(dht_b),
        .mux_out(b)
    );

    // sec/hum_int
    mux_src_4x1_bit #(.BIT_WIDTH(
        9
    )) U_MUX_C (
        .sel(sel),
        .in0(sw_c),
        .in1(wt_c),
        .in2(sr_dist),
        .in3(dht_c),
        .mux_out(c)
    );
      // msec/hum_dec
    mux_src_4x1_bit #(.BIT_WIDTH(
        9
    )) U_MUX_D (
        .sel(sel),
        .in0(sw_d),
        .in1(wt_d),
        .in2(9'd0),
        .in3(dht_d),
        .mux_out(d)
    );



endmodule

module mux_src_4x1_bit #(
    parameter BIT_WIDTH = 9
) (
    input [1:0] sel,
    input [BIT_WIDTH-1:0] in0,
    input [BIT_WIDTH-1:0] in1,
    input [BIT_WIDTH-1:0] in2,
    input [BIT_WIDTH-1:0] in3,
    output reg [BIT_WIDTH-1:0] mux_out
);

    always @(*) begin
        case (sel)
            2'b00: mux_out = in0;
            2'b01: mux_out = in1;
            2'b10: mux_out = in2;
            2'b11: mux_out = in3;

            default mux_out = in0;
        endcase
    end
endmodule
