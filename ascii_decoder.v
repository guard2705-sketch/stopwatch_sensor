module ascii_decoder (
    input        clk,
    input        reset,
    input        empty,    // 수신 FIFO empty 신호
    input  [7:0] rx_data,  // 1 Byte ASCII 입력
    output       pop,      // FIFO Read Enable

    // 명령어 출력 플래그 (1 클록 Pulse)
    output reg o_com_run,
    output reg o_com_clear,
    output reg o_com_mode,
    output reg o_com_opt,
    output reg o_com_lm,  
    output reg o_com_rm, 
    output reg o_com_inc,
    output reg o_com_dec,
    output reg o_com_dht11,
    output reg o_com_sr04,
    output reg o_com_get
);

    // ASCII 정화 상수 정의
    localparam ASCII_SLASH = 8'h2F;  // '/'
    localparam ASCII_LF = 8'h0A;  // '\n' (Enter) Line feed

    // 상태 정의 
    localparam IDLE = 2'b00;
    localparam RECV = 2'b01;
    localparam DEC = 2'b10;

    reg [1:0] state;

    // 최대 8바이트(64bit) 문자열 버퍼 (필요시 크기 조절 가능)
    // 예: "/clear\n" -> 7바이트 저장
    reg [63:0] shift_buf; // UART를 통해 들어오는 1바이트(8비트)짜리 문자를 한 글자씩 밀어 넣어서 저장하는 64비트(8바이트) 크기
    reg [3:0]  byte_cnt;  // 수신된 문자 개수 카운터, 현재 shift_buf 안에 문자가 몇 글자(몇 바이트) 쌓였는지 개수를 세는 4비트 카운터

    // 읽기 신호 (FIFO가 비어있지 않으면 읽음)
    assign pop = !empty;

    // FSM & Shift Register 동작
    always @(posedge clk or posedge reset) begin
        if (reset) begin
            state       <= IDLE;
            shift_buf   <= 64'd0;
            byte_cnt    <= 4'd0;
            o_com_run   <= 1'b0;
            o_com_clear <= 1'b0;
            o_com_mode  <= 1'b0;
            o_com_opt   <= 1'b0;
            o_com_lm    <= 1'b0;  
            o_com_rm    <= 1'b0;
            o_com_inc   <= 1'b0;
            o_com_dec   <= 1'b0;
            o_com_dht11 <= 1'b0;
            o_com_sr04  <= 1'b0;
            o_com_get   <= 1'b0;
        end else begin
            // Pulse 출력 자동 리셋 (1 클록 동안만 1 유지)
            o_com_run   <= 1'b0;
            o_com_clear <= 1'b0;
            o_com_mode  <= 1'b0;
            o_com_opt   <= 1'b0;
            o_com_lm    <= 1'b0;  
            o_com_rm    <= 1'b0;
            o_com_inc   <= 1'b0;
            o_com_dec   <= 1'b0;
            o_com_dht11 <= 1'b0;
            o_com_sr04  <= 1'b0;
            o_com_get   <= 1'b0;
            case (state)
                // 1. 명령어 시작 기호 ('/') 기다리기
                IDLE: begin
                    if (!empty && (rx_data == ASCII_SLASH)) begin
                        shift_buf <= {56'd0, rx_data};  // 첫 문자로 '/' 저장
                        byte_cnt <= 4'd1;
                        state <= RECV;
                    end
                end

                // 2. 종결 문자('\n')를 만날 때까지 버퍼에 쌓기
                RECV: begin
                    if (!empty) begin
                        if (rx_data == ASCII_LF) begin
                            state <= DEC; // 엔터 들어오면 디코딩 상태로 이행
                        end else begin
                            // Shift Register: 기존 데이터는 왼쪽으로 밀고 새 문자는 LSB에 추가
                            shift_buf <= {shift_buf[55:0], rx_data};
                            byte_cnt  <= byte_cnt + 1'b1;

                            // 버퍼 오버플로우 방지 (8바이트 초과 시 리셋)
                            if (byte_cnt >= 4'd8) state <= IDLE;
                        end
                    end
                end

                // 3. 쌓인 문자열을 통째로 한번에 일괄 비교 (Decode)
                DEC: begin
                    case (byte_cnt)

                        4'd3: begin // 4바이트 명령어 (예: /lm, /rm)
                            if (shift_buf[23:0] == "/lm" || shift_buf[23:0] == "/LM")
                                o_com_lm <= 1'b1;
                            else if (shift_buf[23:0] == "/rm" || shift_buf[23:0] == "/RM")
                                o_com_rm <= 1'b1;

                        end


                        4'd4: begin  // 4바이트 명령어 (예: /run,)
                            if (shift_buf[31:0] == "/opt" || shift_buf[31:0] == "/OPT")
                                o_com_opt <= 1'b1;
                            else if (shift_buf[31:0] == "/inc" || shift_buf[31:0] == "/INC")
                                o_com_inc <= 1'b1;
                            else if (shift_buf[31:0] == "/dec" || shift_buf[31:0] == "/DEC")
                                o_com_dec <= 1'b1;
                            else if (shift_buf[31:0] == "/run" || shift_buf[31:0] == "/RUN")
                                o_com_run <= 1'b1;
                            else if (shift_buf[31:0] == "/get" || shift_buf[31:0] == "/GET")
                                o_com_get <= 1'b1;
                        end

                        4'd5: begin // 5바이트 명령어 (예: /mode, /down, /sr04)
                            if (shift_buf[39:0] == "/mode" || shift_buf[39:0] == "/MODE")
                                o_com_mode <= 1'b1;
                            else if (shift_buf[39:0] == "/sr04" || shift_buf[39:0] == "/SR04")
                                o_com_sr04 <= 1'b1;
                        end

                        4'd6: begin  // 6바이트 명령어 (예: /clear)
                            if (shift_buf[47:0] == "/clear" || shift_buf[47:0] == "/CLEAR")
                                o_com_clear <= 1'b1;
                            else if (shift_buf[47:0] == "/dht11" || shift_buf[47:0] == "/DHT11")
                                o_com_dht11 <= 1'b1; 
                        end
                    endcase

                    state    <= IDLE;
                    byte_cnt <= 4'd0;
                end
            endcase
        end
    end

endmodule
