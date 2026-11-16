`timescale 1ns / 1ps


module uart_fifo (

    input  clk,
    input  reset,
    input  rx,
    output tx,

    input pop,
    output [7:0] rx_data,
    output empty,

    input push,
    input [7:0] tx_data,
    output full


);

    wire w_baud_tick_x16;

    // rx 경로 
    wire [7:0] w_rx_data;
    wire       w_rx_done;

    // tx 경로 
    wire [7:0] w_tx_rdata;
    wire       w_tx_empty;
    wire       w_tx_busy;

    baud_tick_x16 U_BADU_TICK_x16 (
        .clk(clk),
        .reset(reset),
        .o_baud_tick(w_baud_tick_x16)
    );

    uart_rx U_UART_RX (
        .clk(clk),
        .reset(reset),
        .i_baud_tick(w_baud_tick_x16),
        .rx(rx),
        .rx_data(w_rx_data),
        .rx_done(w_rx_done)
    );

    fifo U_FIFO_RX (
        .clk  (clk),
        .reset(reset),
        .push (w_rx_done),
        .pop  (pop),
        .wdata(w_rx_data),  // push data
        .rdata(rx_data),    // pop data
        .full (),
        .empty(empty)
    );

    fifo U_FIFO_TX (
        .clk(clk),
        .reset(reset),
        .push(push),
        .pop(~w_tx_busy),
        .wdata(tx_data),  // push data
        .rdata(w_tx_rdata),  // pop data
        .full(full),
        .empty(w_tx_empty)
    );

    uart_tx U_UART_TX (
        .clk(clk),
        .reset(reset),
        .tx_start(~w_tx_empty),
        .tx_data(w_tx_rdata),
        .i_baud_tick(w_baud_tick_x16),
        .tx_busy(w_tx_busy),
        .tx_done(),
        .tx(tx)
    );

endmodule






