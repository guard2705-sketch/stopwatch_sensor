module watch_datapath #(
    parameter MSEC_WIDTH = 7,
    parameter SEC_WIDTH  = 6,
    parameter MIN_WIDTH  = 6,
    parameter HOUR_WIDTH = 5
) (
    input clk,
    input reset,

    // 수동 시간 조절 Enable 신호 (Control Unit / Debounce 모듈에서 발생)
    input hour_inc_en,
    input hour_dec_en,
    input min_inc_en,
    input min_dec_en,


    // FND Controller로 전달될 BCD 변환 전 Binary 시간 데이터
    output [MSEC_WIDTH-1:0] msec,
    output [ SEC_WIDTH-1:0] sec,
    output [ MIN_WIDTH-1:0] min,
    output [HOUR_WIDTH-1:0] hour
);

    // 내부 연동용 Wires
    wire w_tick_100hz;

    wire w_tick_msec;
    wire w_tick_sec;
    wire w_tick_min;
    wire w_tick_hour;

    // =========================================================================
    // 1. Hour Counter (0 ~ 23시)
    // =========================================================================
    watch_time_counter #(
        .BIT_WIDTH (HOUR_WIDTH),
        .TIMES     (24),
        .INIT_VALUE(12)           // 리셋 시 12시로 초기화
    ) U_HOUR_COUNTER (
        .clk       (clk),
        .reset     (reset),
        .i_tick    (w_tick_min),   // 분(Min)에서 넘올 때 1시간 증가
        .inc_en    (hour_inc_en),
        .dec_en    (hour_dec_en),
        .time_count(hour),
        .o_tick    (w_tick_hour)
    );

    // =========================================================================
    // 2. Minute Counter (0 ~ 59분)
    // =========================================================================
    watch_time_counter #(
        .BIT_WIDTH (MIN_WIDTH),
        .TIMES     (60),
        .INIT_VALUE(0)           // 리셋 시 00분으로 초기화
    ) U_MIN_COUNTER (
        .clk       (clk),
        .reset     (reset),
        .i_tick    (w_tick_sec),  // 초(Sec)에서 넘올 때 1분 증가
        .inc_en    (min_inc_en),
        .dec_en    (min_dec_en),
        .time_count(min),
        .o_tick    (w_tick_min)
    );

    // =========================================================================
    // 3. Second Counter (0 ~ 59초)
    // =========================================================================
    watch_time_counter #(
        .BIT_WIDTH (SEC_WIDTH),
        .TIMES     (60),
        .INIT_VALUE(0)           // 리셋 시 00초로 초기화
    ) U_SEC_COUNTER (
        .clk(clk),
        .reset(reset),
        .i_tick    (w_tick_msec),  // 100Hz(10ms) 틱이 100번 쌓이면 1초 증가
        .inc_en(1'b0),
        .dec_en(1'b0),
        .time_count(sec),
        .o_tick(w_tick_sec)
    );

    // =========================================================================
    // 4. Millisecond Counter (0 ~ 99)
    // =========================================================================
    watch_time_counter #(
        .BIT_WIDTH (MSEC_WIDTH),
        .TIMES     (100),
        .INIT_VALUE(0)
    ) U_MSEC_COUNTER (
        .clk       (clk),
        .reset     (reset),
        .i_tick    (w_tick_100hz),
        .inc_en    (1'b0),
        .dec_en    (1'b0),
        .time_count(msec),
        .o_tick    (w_tick_msec)    // msec 최상위 틱은 미사용
    );

    // =========================================================================
    // 5. 100Hz Tick Generator (10ms 주기 pulse 생성)
    // =========================================================================
    watch_tick_gen_100hz U_TICK_GEN_100HZ (
        .clk   (clk),
        .reset (reset),
        .o_tick(w_tick_100hz)
    );

endmodule
module watch_time_counter #(
    parameter BIT_WIDTH = 7,
    TIMES = 100,
    INIT_VALUE = 0
) (
    input clk,
    input reset,
    input clear,
    input i_tick,
    input inc_en,
    input dec_en,
    output [BIT_WIDTH-1:0] time_count,
    output reg o_tick
);

    reg [$clog2(TIMES)-1:0] count_reg;
    assign time_count = count_reg;


    always @(posedge clk or posedge reset) begin
        if (reset | clear) begin
            count_reg <= INIT_VALUE;
            o_tick    <= 1'b0;
        end else begin
            // o_tick은 기본적으로 0 유지 (오버플로우 순간 1클락만 High가 됨)
            o_tick <= 1'b0;

            // Priority 1: 수동 증가 버튼
            if (inc_en) begin
                if (count_reg == (TIMES - 1)) count_reg <= 0;
                else count_reg <= count_reg + 1;
            end  // Priority 2: 수동 감소 버튼
            else if (dec_en) begin
                if (count_reg == 0) count_reg <= TIMES - 1;
                else count_reg <= count_reg - 1;
            end
        // Priority 3: 하위 모듈에서 넘어온 자동 타이머 틱 (시계 흐름의 핵심!)
            else if (i_tick) begin
                if (count_reg == (TIMES - 1)) begin
                    count_reg <= 0;
                    o_tick    <= 1'b1; // 상위 단위(예: 초->분, 분->시)로 틱 발생
                end else begin
                    count_reg <= count_reg + 1;
                end
            end
        end
    end

endmodule

module watch_tick_gen_100hz (
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
