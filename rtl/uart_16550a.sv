module uart_16550a (
    input  logic       clk,
    input  logic       rst,

    input  logic       req_valid,
    output logic       req_ready,
    input  logic       req_write,
    input  logic [2:0] req_addr,
    input  logic [7:0] req_wdata,
    output logic [7:0] rsp_rdata,
    output logic       rsp_valid,

    input  logic       rx,
    output logic       tx,
    output logic       irq
);
    // ================================================================
    // Internal Signals
    // ================================================================

    // Configuration
    logic [15:0] baud_div;
    logic        fcr_fifo_en;
    logic [1:0]  lcr_word_len;
    logic        lcr_stop_bits;
    logic        lcr_parity_en;
    logic        lcr_parity_even;
    logic        lcr_parity_stick;
    logic        lcr_break_en;
    logic        ier_erbi;
    logic        ier_etbei;
    logic        ier_elsi;
    logic        ier_edssi;

    // RX Datapath
    logic [7:0]  rx_data;
    logic        rx_valid;
    logic        rx_pe;
    logic        rx_fe;
    logic        rx_bi;

    logic        rx_fifo_rst;
    logic        rx_fifo_push;
    logic        rx_fifo_pop;
    logic [10:0] rx_fifo_wdata;
    logic [10:0] rx_fifo_rdata;
    logic        rx_fifo_empty;
    logic        rx_fifo_full;
    logic [4:0]  rx_fifo_count;
    logic [4:0]  rx_fifo_trigger_threshold;

    logic        rx_fifo_successful_push;
    logic        rx_fifo_successful_pop;
    logic        rx_fifo_trigger_met;
    logic        rx_fifo_effective_full;

    // RX Error Tracking
    logic        rx_fifo_push_err;
    logic        rx_fifo_pop_err;
    logic        rx_fifo_err_present;
    logic [4:0]  rx_fifo_err_count;
    logic        rx_fifo_overrun_event;
    logic        rx_fifo_head_update;
    logic        rx_fifo_head_has_err;
    logic        rx_fifo_head_err_cleared;
    logic        rx_fifo_pending_err;

    // TX Datapath
    logic       tx_fifo_rst;
    logic       tx_fifo_push;
    logic       tx_fifo_pop;
    logic [7:0] tx_fifo_wdata;
    logic [7:0] tx_fifo_rdata;
    logic       tx_fifo_empty;
    logic       tx_fifo_full;

    logic       tx_start;
    logic [7:0] tx_data;
    logic       tx_ready;
    logic       tsr_empty;

    // Line Status and Interrupts
    logic        lsr_oe;
    logic        lsr_pe;
    logic        lsr_fe;
    logic        lsr_bi;
    logic        lsr_err_ack;
    logic        iir_read;
    logic [3:0]  irq_id;

    // ================================================================
    // 16550A Registers and Control
    // ================================================================

    uart_16550a_regs uart_regs (
        .clk                       (clk),
        .rst                       (rst),
        .req_valid                 (req_valid),
        .req_ready                 (req_ready),
        .req_write                 (req_write),
        .req_addr                  (req_addr),
        .req_wdata                 (req_wdata),
        .rsp_rdata                 (rsp_rdata),
        .rsp_valid                 (rsp_valid),
        .baud_div                  (baud_div),
        .fcr_fifo_en               (fcr_fifo_en),
        .lcr_word_len              (lcr_word_len),
        .lcr_stop_bits             (lcr_stop_bits),
        .lcr_parity_en             (lcr_parity_en),
        .lcr_parity_even           (lcr_parity_even),
        .lcr_parity_stick          (lcr_parity_stick),
        .lcr_break_en              (lcr_break_en),
        .ier_erbi                  (ier_erbi),
        .ier_etbei                 (ier_etbei),
        .ier_elsi                  (ier_elsi),
        .ier_edssi                 (ier_edssi),
        .tsr_empty                 (tsr_empty),
        .tx_fifo_empty             (tx_fifo_empty),
        .tx_fifo_rst               (tx_fifo_rst),
        .tx_fifo_push              (tx_fifo_push),
        .tx_fifo_wdata             (tx_fifo_wdata),
        .rx_fifo_rdata             (rx_fifo_rdata),
        .rx_fifo_empty             (rx_fifo_empty),
        .rx_fifo_overrun_event     (rx_fifo_overrun_event),
        .rx_fifo_head_update       (rx_fifo_head_update),
        .rx_fifo_pending_err       (rx_fifo_pending_err),
        .rx_fifo_rst               (rx_fifo_rst),
        .rx_fifo_pop               (rx_fifo_pop),
        .rx_fifo_trigger_threshold (rx_fifo_trigger_threshold),
        .lsr_oe                    (lsr_oe),
        .lsr_pe                    (lsr_pe),
        .lsr_fe                    (lsr_fe),
        .lsr_bi                    (lsr_bi),
        .lsr_err_ack               (lsr_err_ack),
        .iir_read                  (iir_read),
        .irq_id                    (irq_id)
    );

    // ================================================================
    // RX Engine
    // ================================================================

    assign rx_fifo_push             = rx_valid;
    assign rx_fifo_wdata            = {rx_bi, rx_fe, rx_pe, rx_data};
    assign rx_fifo_successful_push  = rx_fifo_push && !rx_fifo_effective_full;
    assign rx_fifo_successful_pop   = rx_fifo_pop && !rx_fifo_empty;
    assign rx_fifo_trigger_met      = (rx_fifo_count >= rx_fifo_trigger_threshold);
    assign rx_fifo_effective_full   = fcr_fifo_en ? rx_fifo_full : !rx_fifo_empty;
    assign rx_fifo_push_err         = rx_fifo_push && !rx_fifo_effective_full && |rx_fifo_wdata[10:8];
    assign rx_fifo_pop_err          = rx_fifo_pop && !rx_fifo_empty && |rx_fifo_rdata[10:8];
    assign rx_fifo_err_present      = (rx_fifo_err_count != 0);
    assign rx_fifo_overrun_event    = rx_fifo_push && rx_fifo_effective_full;
    assign rx_fifo_head_update      = (rx_fifo_pop && !rx_fifo_empty) || (rx_fifo_push && rx_fifo_empty); // Push on empty or pop on not empty
    assign rx_fifo_head_has_err     = !rx_fifo_empty && |rx_fifo_rdata[10:8];
    assign rx_fifo_head_err_cleared = rx_fifo_head_has_err && lsr_err_ack;
    assign rx_fifo_pending_err      = (rx_fifo_err_count > 1) || (rx_fifo_err_count == 1 && !rx_fifo_head_err_cleared);

    always_ff @(posedge clk) begin
        if (rst || rx_fifo_rst) begin
            rx_fifo_err_count <= 0;
        end
        else if (rx_fifo_push_err && !rx_fifo_pop_err) begin
            rx_fifo_err_count <= rx_fifo_err_count + 1;
        end
        else if (!rx_fifo_push_err && rx_fifo_pop_err) begin
            rx_fifo_err_count <= rx_fifo_err_count - 1;
        end
    end

    uart_16550a_rx uart_rx (
        .clk              (clk),
        .rst              (rst),
        .baud_div         (baud_div),
        .rx               (rx),
        .rx_data          (rx_data),
        .rx_valid         (rx_valid),
        .rx_pe            (rx_pe),
        .rx_fe            (rx_fe),
        .rx_bi            (rx_bi),
        .lcr_word_len     (lcr_word_len),
        .lcr_parity_en    (lcr_parity_en),
        .lcr_parity_even  (lcr_parity_even),
        .lcr_parity_stick (lcr_parity_stick)
    );

    uart_16550a_sync_fifo #(
        .WIDTH (11),
        .DEPTH (16)
    ) rx_fifo (
        .clk   (clk),
        .rst   (rst || rx_fifo_rst),
        .push  (rx_fifo_push),
        .pop   (rx_fifo_pop),
        .wdata (rx_fifo_wdata),
        .rdata (rx_fifo_rdata),
        .empty (rx_fifo_empty),
        .full  (rx_fifo_full),
        .count (rx_fifo_count)
    );

    // ================================================================
    // TX Engine
    // ================================================================

    assign tx_start    = tx_ready && !tx_fifo_empty;
    assign tx_fifo_pop = tx_start;
    assign tx_data     = tx_fifo_rdata;

    uart_16550a_sync_fifo #(
        .WIDTH (8),
        .DEPTH (16)
    ) tx_fifo (
        .clk   (clk),
        .rst   (rst || tx_fifo_rst),
        .push  (tx_fifo_push),
        .pop   (tx_fifo_pop),
        .wdata (tx_fifo_wdata),
        .rdata (tx_fifo_rdata),
        .empty (tx_fifo_empty),
        .full  (tx_fifo_full),
        .count ()
    );

    uart_16550a_tx uart_tx (
        .clk              (clk),
        .rst              (rst),
        .baud_div         (baud_div),
        .tx_start         (tx_start),
        .tx_data          (tx_data),
        .tx_ready         (tx_ready),
        .tx               (tx),
        .lcr_word_len     (lcr_word_len),
        .lcr_stop_bits    (lcr_stop_bits),
        .lcr_parity_en    (lcr_parity_en),
        .lcr_parity_even  (lcr_parity_even),
        .lcr_parity_stick (lcr_parity_stick),
        .lcr_break_en     (lcr_break_en),
        .tsr_empty        (tsr_empty)
    );

    // ================================================================
    // Interrupt Controller
    // ================================================================

    uart_16550a_intc uart_intc (
        .clk                     (clk),
        .rst                     (rst),
        .erbi                    (ier_erbi),
        .etbei                   (ier_etbei),
        .elsi                    (ier_elsi),
        .edssi                   (ier_edssi),
        .fcr_fifo_en             (fcr_fifo_en),
        .lcr_word_len            (lcr_word_len),
        .lcr_stop_bits           (lcr_stop_bits),
        .lcr_parity_en           (lcr_parity_en),
        .baud_div                (baud_div),
        .rx_oe                   (lsr_oe),
        .rx_pe                   (lsr_pe),
        .rx_fe                   (lsr_fe),
        .rx_bi                   (lsr_bi),
        .iir_read                (iir_read),
        .rx_fifo_trigger_met     (rx_fifo_trigger_met),
        .rx_fifo_empty           (rx_fifo_empty),
        .rx_fifo_successful_push (rx_fifo_successful_push),
        .rx_fifo_successful_pop  (rx_fifo_successful_pop),
        .tx_fifo_push            (tx_fifo_push),
        .tx_fifo_full            (tx_fifo_full),
        .tx_fifo_empty           (tx_fifo_empty),
        .irq_id                  (irq_id),
        .irq                     (irq)
    );
endmodule
