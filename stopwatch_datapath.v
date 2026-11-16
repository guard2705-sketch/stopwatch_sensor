module stopwatch_datapath #(
    parameter MSEC_WIDTH = 7,
    SEC_WIDTH = 6,
    MIN_WIDTH = 6,
    HOUR_WIDTH = 5
) (
    input clk,
    input reset,
    input run_stop,
    input clear,
    input mode,
    input min_inc,
    input save,


    output [MSEC_WIDTH-1:0] msec,
    output [SEC_WIDTH-1:0] sec,
    output [MIN_WIDTH-1:0] min,
    output [HOUR_WIDTH-1:0] hour,
    output blink_onoff
);

    wire w_tick_100hz, w_tick_sec, w_tick_min, w_tick_hour;

    wire [HOUR_WIDTH-1:0] w_hour;
    wire [MIN_WIDTH-1:0] w_min;
    wire [SEC_WIDTH-1:0] w_sec;
    wire [MSEC_WIDTH-1:0] w_msec;


    reg [4:0] cap_hour;
    reg [5:0] cap_min;
    reg [5:0] cap_sec;
    reg [6:0] cap_msec;
    reg [$clog2(1000)-1:0] blink_counter;
    reg blink_onoff_reg;

    assign blink_onoff = blink_onoff_reg;

    wire timer_expired = (mode==1)&&(hour==0)&&(min==0)&&(sec==0)&&(msec==0);


    // 시간 capture register
    always @(posedge clk, posedge reset) begin
        if (reset) begin
            cap_hour <= 0;
            cap_min  <= 0;
            cap_sec  <= 0;
            cap_msec <= 0;
        end else if (!run_stop) begin
            cap_hour <= w_hour;
            cap_min  <= w_min;
            cap_sec  <= w_sec;
            cap_msec <= w_msec;
        end

    end


    always @(posedge w_tick_100hz, posedge reset) begin
        if (reset) begin
            blink_counter   <= 0;
            blink_onoff_reg <= 0;
        end else if (timer_expired) blink_onoff_reg <= 1;
        else if ((msec == 0 && sec == 0) && (~(hour == 0 && min == 0)))
            blink_onoff_reg <= 1;
        else if (blink_onoff_reg == 1) begin
            blink_counter <= blink_counter + 1;
            if (blink_counter >= 1000) begin
                blink_counter   <= 0;
                blink_onoff_reg <= 0;
            end
        end
    end




    mux_2x1_bit #(
        .BIT_WIDTH(5)
    ) HOUR_MUX (

        .sel(save),
        .in0(w_hour),
        .in1(cap_hour),
        .mux_out(hour)
    );

    mux_2x1_bit #(
        .BIT_WIDTH(6)
    ) MIN_MUX (
        .sel(save),
        .in0(w_min),
        .in1(cap_min),
        .mux_out(min)
    );

    mux_2x1_bit #(
        .BIT_WIDTH(6)
    ) SEC_MUX (
        .sel(save),
        .in0(w_sec),
        .in1(cap_sec),
        .mux_out(sec)
    );

    mux_2x1_bit #(
        .BIT_WIDTH(7)
    ) MSEC_MUX (
        .sel(save),
        .in0(w_msec),
        .in1(cap_msec),
        .mux_out(msec)
    );



    wire timer_set_min = (mode == 1'b1 && !run_stop) ? min_inc : 1'b0;

    stopwatch_time_counter #(
        .BIT_WIDTH(HOUR_WIDTH),
        .TIMES(24)
    ) U_HOUR_COUNTER (
        .clk(clk),
        .reset(reset),
        .i_tick(w_tick_hour),
        .inc(1'b0),
        .mode(mode),
        .run_stop(run_stop),
        .clear(clear),
        .time_count(w_hour),
        .o_tick()
    );




    stopwatch_time_counter #(
        .BIT_WIDTH(MIN_WIDTH),
        .TIMES(60)
    ) U_MIN_COUNTER (
        .clk(clk),
        .reset(reset),
        .i_tick(w_tick_min),
        .inc(timer_set_min),
        .mode(mode),
        .run_stop(run_stop),
        .clear(clear),
        .time_count(w_min),
        .o_tick(w_tick_hour)
    );




    stopwatch_time_counter #(
        .BIT_WIDTH(SEC_WIDTH),
        .TIMES(60)
    ) U_SEC_COUNTER (
        .clk(clk),
        .reset(reset),
        .i_tick(w_tick_sec),
        .inc(1'b0),
        .mode(mode),
        .run_stop(run_stop),
        .clear(clear),
        .time_count(w_sec),
        .o_tick(w_tick_min)
    );



    stopwatch_time_counter #(
        .BIT_WIDTH(MSEC_WIDTH),
        .TIMES(100)
    ) U_MSEC_COUNTER (
        .clk(clk),
        .reset(reset),
        .i_tick(w_tick_100hz),
        .inc(1'b0),
        .mode(mode),
        .run_stop(run_stop),
        .clear(clear),
        .time_count(w_msec),
        .o_tick(w_tick_sec)
    );

    stopwatch_tick_gen_100hz U_TICK_GEN_100HZ (
        .clk(clk),
        .reset(reset),
        .o_tick(w_tick_100hz)
    );

endmodule




module stopwatch_time_counter #(
    parameter BIT_WIDTH = 7,
    TIMES = 100
) (
    input clk,
    input reset,
    input i_tick,
    input mode,
    input run_stop,
    input clear,
    input inc,
    output [BIT_WIDTH-1:0] time_count,
    output reg o_tick
);

    reg [$clog2(TIMES)-1:0] count_reg;
    assign time_count = count_reg;


    always @(posedge clk, posedge reset) begin
        if (reset | clear) begin
            count_reg <= 0;
            o_tick <= 1'b0;
        end else begin
            o_tick <= 1'b0;

            if (inc) begin
                if (count_reg == (TIMES - 1)) count_reg <= 0;
                else count_reg <= count_reg + 1'b1;
            end else if (i_tick & run_stop) begin
                if (!mode) begin  // Up-count
                    if (count_reg == (TIMES - 1)) begin
                        count_reg <= 0;
                        o_tick    <= 1'b1;
                    end else begin
                        count_reg <= count_reg + 1'b1;
                    end
                end else begin  // Down-count
                    if (count_reg == 0) begin
                        count_reg <= (TIMES - 1);
                        o_tick    <= 1'b1;
                    end else begin
                        count_reg <= count_reg - 1'b1;
                    end
                end
            end
        end
    end
endmodule


module stopwatch_tick_gen_100hz (
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

module mux_2x1_bit #(
    parameter BIT_WIDTH = 5
) (
    input sel,
    input [BIT_WIDTH-1:0] in0,
    input [BIT_WIDTH-1:0] in1,
    output [BIT_WIDTH-1:0] mux_out
);

    assign mux_out = (sel) ? in1 : in0;
endmodule
