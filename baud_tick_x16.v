module baud_tick_x16 (
    input  clk,
    input  reset,
    output o_baud_tick
);
    // 9600bps baud tick gen 1/9600s 9600hz
    // tick count = input freg/ baud_tick_freq
    parameter F_COUNT = 100_000_000 / (9600 * 16);

    reg  [$clog2(F_COUNT)-1:0] count_reg;
    wire [$clog2(F_COUNT)-1:0] count_next;

    always @(posedge clk, posedge reset) begin
        if (reset) begin
            count_reg <= 0;
        end else begin
            count_reg <= count_next;
        end
    end

    assign count_next  = (count_reg == (F_COUNT - 1)) ? 0 : count_reg + 1;
    // output CL
    assign o_baud_tick = (count_reg == (F_COUNT - 1)) ? 1 : 0;

endmodule
