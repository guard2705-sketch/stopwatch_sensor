`timescale 1ns / 1ps

// uart_fifo 파형 확인용 (간단 버전, 실제 9600bps)
//   1) PC가 rx로 'I'(0x49)를 보낸다  -> FIFO에 들어오고 pop으로 꺼낸다
//   2) push로 'J'(0x4A)를 넣는다     -> tx 선으로 나간다
//
//   파형 확인용 신호
//     o_baud_tick : baud_tick_x16 (6.5us마다 펄스)
//     tick16      : baud tick을 16개 셀 때마다 1클럭 펄스 (= 비트 하나, 약 104us)
module tb_uart_fifo;

    reg        clk;
    reg        reset;
    reg        rx;
    reg        pop;
    reg        push;
    reg  [7:0] tx_data;

    wire       tx;
    wire [7:0] rx_data;
    wire       empty;
    wire       full;
    wire       o_baud_tick;

    uart_fifo DUT (
        .clk(clk),
        .reset(reset),
        .rx(rx),
        .tx(tx),
        .pop(pop),
        .rx_data(rx_data),
        .empty(empty),
        .push(push),
        .tx_data(tx_data),
        .full(full)
    );

    // baud tick을 TB 최상위에서 보기 위한 복사본 (DUT 안의 것과 같은 파형)
    baud_tick_x16 U_BAUD_MON (
        .clk(clk),
        .reset(reset),
        .o_baud_tick(o_baud_tick)
    );

    // 100MHz 클럭
    always #5 clk = ~clk;

    // ------------------------------------------------------------------
    // baud tick 16개를 셀 때마다 tick16 을 1클럭 동안 1로 만든다
    //   - 새 글자의 시작 비트(rx가 1->0)가 보이면 카운터를 처음부터 센다
    //   - 그래서 tick16 펄스는 비트가 끝나는 지점(다음 비트가 시작하는 지점)에 나온다
    //   - 글자 하나에 10번 나온다 (시작 1 + 데이터 8 + 정지 1)
    // ------------------------------------------------------------------
    reg [4:0] tick_cnt;
    reg       tick16;
    reg       rx_d;      // 한 클럭 전의 rx

    always @(posedge clk or posedge reset) begin
        if (reset) begin
            tick_cnt <= 0;
            tick16   <= 0;
            rx_d     <= 1;
        end else begin
            rx_d   <= rx;
            tick16 <= 0;

            if (rx_d == 1 && rx == 0 && DUT.U_UART_RX.c_state == 0) begin
                tick_cnt <= 0;               // 새 글자가 시작됨 : 처음부터 다시 셈
            end else if (o_baud_tick) begin
                if (tick_cnt == 15) begin
                    tick_cnt <= 0;
                    tick16   <= 1;           // baud tick 16개를 셌다 -> 펄스
                end else begin
                    tick_cnt <= tick_cnt + 1;
                end
            end
        end
    end

    // 9600bps 한 비트 시간 (ns)
    parameter BIT_TIME = 104167;

    // PC가 rx 선으로 한 글자 보내기: 시작비트 0 -> 데이터 8비트(LSB부터) -> 정지비트 1
    task send_rx;
        input [7:0] data;
        integer k;
        begin
            rx = 0;
            #(BIT_TIME);
            for (k = 0; k < 8; k = k + 1) begin
                rx = data[k];
                #(BIT_TIME);
            end
            rx = 1;
            #(BIT_TIME);
        end
    endtask

    initial begin
        clk = 0;
        reset = 1;
        rx = 1;
        pop = 0;
        push = 0;
        tx_data = 0;

        #100;
        reset = 0;
        #100;

        // 1) PC -> FPGA : 'I'
        send_rx(8'h49);
        #1000;
        pop = 1;      // 한 글자 꺼내기 (1클럭)
        #10;
        pop = 0;

        // 2) FPGA -> PC : 'J'
        #1000;
        tx_data = 8'h4A;
        push = 1;     // 한 글자 넣기 (1클럭)
        #10;
        push = 0;

        #(BIT_TIME * 12);
        $finish;
    end

endmodule