module uart_16550a_regs (
    input  logic        clk,
    input  logic        rst,

    input  logic        req_valid,
    output logic        req_ready,
    input  logic        req_write,
    input  logic [2:0]  req_addr,
    input  logic [7:0]  req_wdata,
    output logic [7:0]  rsp_rdata,
    output logic        rsp_valid,

    output logic [15:0] baud_div,
    output logic        fcr_fifo_en,
    output logic [1:0]  fcr_rx_trigger,
    output logic [1:0]  lcr_word_len,
    output logic        lcr_stop_bits,
    output logic        lcr_parity_en,
    output logic        lcr_parity_even,
    output logic        lcr_parity_stick,
    output logic        lcr_break_en,
    output logic        ier_erbi,
    output logic        ier_etbei,
    output logic        ier_elsi,
    output logic        ier_edssi,

    output logic        fcr_write,
    output logic        thr_write,
    output logic        rbr_read,
    output logic        iir_read,
    output logic        fifo_en_toggle,

    input  logic        tsr_empty,
    input  logic        tx_fifo_empty,

    input  logic [10:0] rx_fifo_rdata,
    input  logic        rx_fifo_empty,
    input  logic        rx_fifo_overrun_event,
    input  logic        rx_fifo_head_update,
    input  logic [4:0]  rx_fifo_err_count,
    input  logic        rx_fifo_head_has_err,

    output logic        lsr_oe,
    output logic        lsr_pe,
    output logic        lsr_fe,
    output logic        lsr_bi,

    input  logic [3:0]  irq_id
);
    import uart_16550a_pkg::*;

    // ================================================================
    // Request Decoding and Response Generation
    // ================================================================

    logic req_re;
    logic req_we;

    assign req_re    = req_valid && ~req_write;
    assign req_we    = req_valid && req_write;
    assign req_ready = 1'b1;

    // Pulse high for one cycle after a valid request
    always_ff @(posedge clk) begin
        if (rst) rsp_valid <= 0;
        else     rsp_valid <= req_valid;
    end

    // ================================================================
    // 16550A Registers
    // ================================================================

    logic [7:0]  dll;
    logic [7:0]  dlm;
    logic [7:0]  fcr;
    logic [7:0]  lcr;
    logic [7:0]  mcr;
    logic [7:0]  ier;
    logic [7:0]  lsr;
    logic [7:0]  msr;
    logic [7:0]  iir;
    logic [7:0]  scr;

    // ================================================================
    // Decoded Register Fields
    // ================================================================

    logic dlab;

    assign dlab             = lcr[7];
    assign baud_div         = {dlm, dll};
    assign fcr_fifo_en      = fcr[0];
    assign fcr_rx_trigger   = fcr[7:6];
    assign lcr_word_len     = lcr[1:0];
    assign lcr_stop_bits    = lcr[2];
    assign lcr_parity_en    = lcr[3];
    assign lcr_parity_even  = lcr[4];
    assign lcr_parity_stick = lcr[5];
    assign lcr_break_en     = lcr[6];
    assign ier_erbi         = ier[0];
    assign ier_etbei        = ier[1];
    assign ier_elsi         = ier[2];
    assign ier_edssi        = ier[3];

    // ================================================================
    // System Actions
    // ================================================================

    logic lsr_read;

    assign fcr_write      = req_we && (req_addr == CSR_FCR);
    assign lsr_read       = req_re && (req_addr == CSR_LSR);
    assign thr_write      = req_we && (req_addr == CSR_THR) && !dlab;
    assign rbr_read       = req_re && (req_addr == CSR_RBR) && !dlab;
    assign iir_read       = req_re && (req_addr == CSR_IIR);
    assign fifo_en_toggle = fcr_write && (req_wdata[0] != fcr_fifo_en);

    // ================================================================
    // Driving LSR and IIR
    // ================================================================

    logic overrun_err;
    logic lsr_err_ack;

    logic rx_fifo_head_err_cleared;
    logic rx_fifo_pending_err;

    always_ff @(posedge clk) begin
        if (rst) begin
            overrun_err <= 0;
            lsr_err_ack <= 0;
        end
        else begin
            if (rx_fifo_overrun_event) overrun_err <= 1;
            else if (lsr_read)         overrun_err <= 0;

            if (rx_fifo_head_update) lsr_err_ack <= 0;
            else if (lsr_read)       lsr_err_ack <= 1;
        end
    end

    assign rx_fifo_head_err_cleared = rx_fifo_head_has_err && lsr_err_ack;
    assign rx_fifo_pending_err      = (rx_fifo_err_count > 1) || (rx_fifo_err_count == 1 && !rx_fifo_head_err_cleared);

    assign lsr_oe = overrun_err;
    assign lsr_pe = !rx_fifo_empty && (rx_fifo_rdata[8]  && !lsr_err_ack);
    assign lsr_fe = !rx_fifo_empty && (rx_fifo_rdata[9]  && !lsr_err_ack);
    assign lsr_bi = !rx_fifo_empty && (rx_fifo_rdata[10] && !lsr_err_ack);
    // can't get rid of rx_fifo_empty i think because of rotating pointers

    assign lsr[0] = !rx_fifo_empty;
    assign lsr[1] = lsr_oe;
    assign lsr[2] = lsr_pe;
    assign lsr[3] = lsr_fe;
    assign lsr[4] = lsr_bi;
    assign lsr[5] = tx_fifo_empty;
    assign lsr[6] = tx_fifo_empty && tsr_empty;
    assign lsr[7] = fcr_fifo_en && rx_fifo_pending_err;

    assign iir[7:4] = {fcr_fifo_en, fcr_fifo_en, 2'b00};
    assign iir[3:0] = irq_id;

    // ================================================================
    // Register R/W
    // ================================================================

    always_ff @(posedge clk) begin
        if (rst) begin
            dll <= 0;
            dlm <= 0;
            fcr <= 0;
            lcr <= 0;
            mcr <= 0;
            ier <= 0;
            scr <= 0;
        end
        else if (req_we) begin
            unique0 case (req_addr)
                CSR_LCR: lcr <= req_wdata;
                CSR_MCR: mcr <= req_wdata & MCR_WR_MASK;
                CSR_SCR: scr <= req_wdata;

                CSR_THR: begin
                    if (dlab) dll <= req_wdata;
                    // THR writes are handled in tx_fifo_push
                end
                CSR_FCR: begin
                    if (req_wdata[0]) fcr <= req_wdata & FCR_WR_MASK; // RX/TX FIFO reset pins not registered; checked combinationally
                    else              fcr <= req_wdata & 8'h01;
                end
                CSR_IER: begin
                    if (dlab) dlm <= req_wdata;
                    else      ier <= req_wdata & IER_WR_MASK;
                end
            endcase
        end
        else if (req_re) begin
            unique case (req_addr)
                CSR_IIR: rsp_rdata <= iir;
                CSR_LCR: rsp_rdata <= lcr;
                CSR_MCR: rsp_rdata <= mcr;
                CSR_LSR: rsp_rdata <= lsr;
                CSR_MSR: rsp_rdata <= msr;
                CSR_SCR: rsp_rdata <= scr;

                CSR_RBR: begin
                    if (dlab) rsp_rdata <= dll;
                    else      rsp_rdata <= rx_fifo_rdata[7:0];
                end
                CSR_IER: begin
                    if (dlab) rsp_rdata <= dlm;
                    else      rsp_rdata <= ier;
                end
            endcase
        end
    end
endmodule
// reorder signals to have fifo inputs after bus so that all after is output ?? irq_id too ??
