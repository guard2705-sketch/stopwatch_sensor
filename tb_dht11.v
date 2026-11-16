`timescale 1ns / 1ps

// dht11 테스트
//   tb가 DHT11 센서 역할을 한다.
//     FPGA : 선을 19ms 동안 Low로 유지 -> 선을 놓음
//     센서 : 30us 뒤 응답(Low 80us, High 80us) -> 40비트 전송
//            비트마다 Low 50us + High (0이면 26us, 1이면 70us)
//            마지막에 Low 50us 한 번 더
//
//   보내는 데이터 : 습도 60.0, 온도 28.1, 체크섬 0x59 (= 60+0+28+1)
//   기대 결과     : humidity = 3c00, temperature = 1c01, valid = 1
module tb_dht11;

    reg clk = 0;
    reg reset = 1;
    always #5 clk = ~clk;  // 100MHz

    reg  start = 0;
    wire [15:0] temperature, humidity;
    wire done, valid;

    // 양방향 선 : 센서가 선을 잡지 않으면 풀업저항 때문에 1
    wire dht11_io;
    pullup (dht11_io);

    reg sensor_en  = 0;    // 1이면 센서가 선을 구동
    reg sensor_val = 1;    // 센서가 내보내는 값
    assign dht11_io = sensor_en ? sensor_val : 1'bz;

    dht11 DUT (
        .clk(clk), .reset(reset),
        .start(start),
        .temperature(temperature), .humidity(humidity),
        .done(done), .valid(valid),
        .dht11_io(dht11_io)
    );

    // 센서가 비트 하나 보내기 : Low 50us + High (0이면 26us, 1이면 70us)
    task send_bit(input b);
        begin
            sensor_val = 0;  #50_000;
            sensor_val = 1;
            if (b) #70_000;
            else   #26_000;
        end
    endtask

    // 보낼 데이터 : {습도정수, 습도소수, 온도정수, 온도소수, 체크섬}
    //   체크섬을 일부러 틀리게(예: 8'h00) 바꾸면 valid = 0 이 나온다
    reg [39:0] data = {8'd60, 8'd0, 8'd28, 8'd1, 8'h59};
    integer i;

    initial begin
        #100 reset = 0;
        #100;

        // FPGA가 start 신호를 보냄
        start = 1;  #20;  start = 0;

        // 센서 동작
        wait (dht11_io === 1'b0);   // FPGA가 선을 Low로 내림 (19ms)
        wait (dht11_io === 1'b1);   // FPGA가 선을 놓음
        #30_000;                    // 30us 뒤 응답

        sensor_en = 1;
        sensor_val = 0;  #80_000;   // 응답 Low 80us
        sensor_val = 1;  #80_000;   // 응답 High 80us

        for (i = 39; i >= 0; i = i - 1)
            send_bit(data[i]);      // 40비트 전송 (맨 앞 비트부터)

        sensor_val = 0;  #50_000;   // 마지막 Low 50us
        sensor_en = 0;              // 선을 놓음

        #200_000;
        $finish;
    end

    // done 펄스가 나오면 결과 출력
    always @(posedge done) begin
        #1;
        $display("humidity = %h, temperature = %h, valid = %b", humidity, temperature, valid);
        $display("(기대: humidity = 3c00, temperature = 1c01, valid = 1)");
    end

endmodule