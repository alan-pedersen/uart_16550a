module uart_16550a_rx_status (
    input  logic        clk,
    input  logic        rst,

    input  logic        rx_fifo_push,
    input  logic        rx_fifo_pop,
    input  logic [10:0] rx_fifo_wdata,
    input  logic [10:0] rx_fifo_rdata,
    input  logic        rx_fifo_empty,
    input  logic        rx_fifo_full,
    input  logic [4:0]  rx_fifo_count,

    input  logic        fcr_fifo_en,
    input  logic [1:0]  fcr_rx_trigger,

    output logic        rx_fifo_successful_push,
    output logic        rx_fifo_successful_pop,
    output logic        rx_fifo_overrun_event,
    output logic        rx_fifo_trigger_met,
    output logic [4:0]  rx_fifo_err_count,
    output logic        rx_fifo_head_update,
    output logic        rx_fifo_head_has_err
);
    logic       rx_fifo_effective_full;
    logic [4:0] rx_fifo_trigger_threshold;

    logic       rx_fifo_push_err;
    logic       rx_fifo_pop_err;

    assign rx_fifo_effective_full  = fcr_fifo_en ? rx_fifo_full : !rx_fifo_empty;  
    assign rx_fifo_push_err        = rx_fifo_push && !rx_fifo_effective_full && |rx_fifo_wdata[10:8];
    assign rx_fifo_pop_err         = rx_fifo_pop && !rx_fifo_empty && |rx_fifo_rdata[10:8];

    assign rx_fifo_successful_push = rx_fifo_push && !rx_fifo_effective_full;
    assign rx_fifo_successful_pop  = rx_fifo_pop && !rx_fifo_empty;
    assign rx_fifo_overrun_event   = rx_fifo_push && rx_fifo_effective_full;
    assign rx_fifo_trigger_met     = (rx_fifo_count >= rx_fifo_trigger_threshold);
    assign rx_fifo_head_update     = (rx_fifo_pop && !rx_fifo_empty) || (rx_fifo_push && rx_fifo_empty); // Push on empty or pop on not empty
    assign rx_fifo_head_has_err    = !rx_fifo_empty && |rx_fifo_rdata[10:8];

    always_comb begin
        unique case (fcr_rx_trigger)
            2'b00: rx_fifo_trigger_threshold = 1;
            2'b01: rx_fifo_trigger_threshold = 4;
            2'b10: rx_fifo_trigger_threshold = 8;
            2'b11: rx_fifo_trigger_threshold = 14;
        endcase
    end

    always_ff @(posedge clk) begin
        if (rst) begin
            rx_fifo_err_count <= 0;
        end
        else if (rx_fifo_push_err && !rx_fifo_pop_err) begin
            rx_fifo_err_count <= rx_fifo_err_count + 1;
        end
        else if (!rx_fifo_push_err && rx_fifo_pop_err) begin
            rx_fifo_err_count <= rx_fifo_err_count - 1;
        end
    end
endmodule
