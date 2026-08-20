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
    // 16550A Registers and Control
    // ================================================================

    // Configuration
    logic [15:0] baud_div;
    logic        fcr_fifo_en;
    logic [1:0]  fcr_rx_trigger;
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

    // System Actions (Definitive)
    logic        fcr_write;
    logic        thr_write;
    logic        rbr_read;
    logic        iir_read;
    logic        fifo_en_toggle;

    // Line Status and Interrupts
    logic        lsr_oe;
    logic        lsr_pe;
    logic        lsr_fe;
    logic        lsr_bi;

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
        .fcr_rx_trigger            (fcr_rx_trigger),
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

        .fcr_write                 (fcr_write),
        .thr_write                 (thr_write),
        .rbr_read                  (rbr_read),
        .iir_read                  (iir_read),
        .fifo_en_toggle            (fifo_en_toggle),

        .tsr_empty                 (tsr_empty),
        .tx_fifo_empty             (tx_fifo_empty),

        .rx_fifo_rdata             (rx_fifo_rdata),
        .rx_fifo_empty             (rx_fifo_empty),
        .rx_fifo_overrun_event     (rx_fifo_overrun_event),
        .rx_fifo_head_update       (rx_fifo_head_update),
        .rx_fifo_err_count         (rx_fifo_err_count),
        .rx_fifo_head_has_err      (rx_fifo_head_has_err),

        .lsr_oe                    (lsr_oe),
        .lsr_pe                    (lsr_pe),
        .lsr_fe                    (lsr_fe),
        .lsr_bi                    (lsr_bi),

        .irq_id                    (irq_id)
    );

    // ================================================================
    // RX Engine
    // ================================================================

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

    logic        rx_fifo_successful_push;
    logic        rx_fifo_successful_pop;
    logic        rx_fifo_overrun_event;
    logic        rx_fifo_trigger_met;
    logic [4:0]  rx_fifo_err_count;
    logic        rx_fifo_head_update;
    logic        rx_fifo_head_has_err;

    assign rx_fifo_rst    = rst || fifo_en_toggle || (fcr_write && req_wdata[1]);
    assign rx_fifo_push   = rx_valid;
    assign rx_fifo_pop    = rbr_read;
    assign rx_fifo_wdata  = {rx_bi, rx_fe, rx_pe, rx_data};

    uart_16550a_rx rx_engine (
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
        .rst   (rx_fifo_rst),
        .push  (rx_fifo_push),
        .pop   (rx_fifo_pop),
        .wdata (rx_fifo_wdata),
        .rdata (rx_fifo_rdata),
        .empty (rx_fifo_empty),
        .full  (rx_fifo_full),
        .count (rx_fifo_count)
    );

    uart_16550a_rx_status rx_status ( // rename to rx_fifo_status ??
        .clk                     (clk),
        .rst                     (rx_fifo_rst),
        .rx_fifo_push            (rx_fifo_push),
        .rx_fifo_pop             (rx_fifo_pop),
        .rx_fifo_wdata           (rx_fifo_wdata),
        .rx_fifo_rdata           (rx_fifo_rdata),
        .rx_fifo_empty           (rx_fifo_empty),
        .rx_fifo_full            (rx_fifo_full),
        .rx_fifo_count           (rx_fifo_count),
        .fcr_fifo_en             (fcr_fifo_en),
        .fcr_rx_trigger          (fcr_rx_trigger),
        .rx_fifo_successful_push (rx_fifo_successful_push),
        .rx_fifo_successful_pop  (rx_fifo_successful_pop),
        .rx_fifo_overrun_event   (rx_fifo_overrun_event),
        .rx_fifo_trigger_met     (rx_fifo_trigger_met),
        .rx_fifo_err_count       (rx_fifo_err_count),
        .rx_fifo_head_update     (rx_fifo_head_update),
        .rx_fifo_head_has_err    (rx_fifo_head_has_err)
    );

    // ================================================================
    // TX Engine
    // ================================================================

    logic        tx_fifo_rst;
    logic        tx_fifo_push;
    logic        tx_fifo_pop;
    logic [7:0]  tx_fifo_wdata;
    logic [7:0]  tx_fifo_rdata;
    logic        tx_fifo_empty;
    logic        tx_fifo_full;

    logic        tx_start;
    logic [7:0]  tx_data;
    logic        tx_ready;
    logic        tsr_empty;

    assign tx_fifo_rst    = rst || fifo_en_toggle || (fcr_write && req_wdata[2]);
    assign tx_fifo_push   = thr_write && (fcr_fifo_en || tx_fifo_empty);
    assign tx_fifo_pop    = tx_start;
    assign tx_fifo_wdata  = req_wdata;

    assign tx_start       = tx_ready && !tx_fifo_empty;
    assign tx_data        = tx_fifo_rdata;

    uart_16550a_sync_fifo #(
        .WIDTH (8),
        .DEPTH (16)
    ) tx_fifo (
        .clk   (clk),
        .rst   (tx_fifo_rst),
        .push  (tx_fifo_push),
        .pop   (tx_fifo_pop),
        .wdata (tx_fifo_wdata),
        .rdata (tx_fifo_rdata),
        .empty (tx_fifo_empty),
        .full  (tx_fifo_full),
        .count ()
    );

    uart_16550a_tx tx_engine (
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

    logic [3:0]  irq_id;

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
        .lsr_oe                  (lsr_oe),
        .lsr_pe                  (lsr_pe),
        .lsr_fe                  (lsr_fe),
        .lsr_bi                  (lsr_bi),
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
