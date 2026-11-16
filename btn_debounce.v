`timescale 1ns / 1ps

module btn_debounce(
    input clk,          // 100MHz
    input reset,
    input i_btn,
    output o_btn
    );
    reg [7:0] q_reg;       // 8tab shift register SIPO
    wire btn_debounce;     // output of 8 input AND gate
    
    reg [$clog2(50)-1:0] counter_reg;
    reg o_1mhz;
    
    // 1. clock div : 100Mhz -> 1Mhz
    always @(posedge clk, posedge reset) begin
        if(reset) begin
            counter_reg <= 0;
            o_1mhz <= 0;
        end else begin
            counter_reg <= counter_reg + 1;
            if(counter_reg == (50-1)) begin
                counter_reg <= 0;
                o_1mhz <= ~o_1mhz;
            end
        end
    end

    // 2. 8bit shift register, SIPO (o_1mhz 도메인)
    always @(posedge o_1mhz, posedge reset) begin
        if(reset) begin
            q_reg <= 8'h00;
        end else begin
            q_reg <= {i_btn, q_reg[7:1]};
        end
    end
    
    // 3. 8 bit input AND gate
    assign btn_debounce = &q_reg; 

    // =========================================================================
    // 4. [동기화 추가] 2-Stage Synchronizer + Edge Detector (100MHz 도메인)
    // =========================================================================
    reg sync_0, sync_1;
    reg edge_reg;

    always @(posedge clk, posedge reset) begin
        if(reset) begin
            sync_0   <= 1'b0;
            sync_1   <= 1'b0;
            edge_reg <= 1'b0;
        end else begin
            sync_0   <= btn_debounce; // 1차 동기화 (CDC 메타스태빌리티 흡수)
            sync_1   <= sync_0;       // 2차 동기화 (안정화된 100MHz 신호)
            edge_reg <= sync_1;       // 1클록 지연 저장 (Edge 감지용)
        end
    end

    // sync_1 신호를 기준으로 100MHz 1클록 원샷 펄스 출력
    assign o_btn = sync_1 & (~edge_reg);

endmodule