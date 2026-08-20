module uart_16550a_intc (
    input  logic        clk,
    input  logic        rst,

    input  logic        erbi,
    input  logic        etbei,
    input  logic        elsi,
    input  logic        edssi,

    input  logic        fcr_fifo_en,
    input  logic [1:0]  lcr_word_len,
    input  logic        lcr_stop_bits,
    input  logic        lcr_parity_en,
    input  logic [15:0] baud_div,

    input  logic        lsr_oe,
    input  logic        lsr_pe,
    input  logic        lsr_fe,
    input  logic        lsr_bi,

    input  logic        iir_read,
    input  logic        rx_fifo_trigger_met,
    input  logic        rx_fifo_empty,
    input  logic        rx_fifo_successful_push,
    input  logic        rx_fifo_successful_pop,
    input  logic        tx_fifo_push,
    input  logic        tx_fifo_full,
    input  logic        tx_fifo_empty,

    output logic [3:0]  irq_id,
    output logic        irq
);
    import uart_16550a_pkg::*;

    // ================================================================
    // THRE Interrupt
    // ================================================================

    logic thre_active;
    logic thre_ack;

    assign thre_active = (irq_id == IIR_THRE);

    always_ff @(posedge clk) begin
        if (rst) begin
            thre_ack <= 0;
        end
        else begin
            if (tx_fifo_push && !tx_fifo_full) thre_ack <= 0;
            else if (iir_read && thre_active)  thre_ack <= 1;
        end
    end

    // ================================================================
    // Timeout Interrupt
    // ================================================================

    logic [9:0]  start_ticks;
    logic [9:0]  data_ticks;
    logic [9:0]  parity_ticks;
    logic [9:0]  stop_ticks;
    logic [9:0]  timeout_ticks;

    logic [15:0] cti_baud_div_q;
    logic [15:0] cti_baud_cnt;
    logic        cti_baud_tick_16x;

    logic [9:0]  cti_cnt;
    logic        cti_clear;
    logic        cti;

    assign start_ticks   = (1 * 16) * 4;
    assign data_ticks    = ((5 + 10'(lcr_word_len)) * 16) * 4;
    assign parity_ticks  = (lcr_parity_en * 16) * 4;
    assign stop_ticks    = (10'(calc_stop_ticks(lcr_word_len, lcr_stop_bits)) + 1) * 4; // calc_stop_ticks returns 1,1.5,2 * 16 - 1, need to add 1
    assign timeout_ticks = start_ticks + data_ticks + parity_ticks + stop_ticks;

    assign cti_clear     = rx_fifo_successful_pop || (!cti && rx_fifo_successful_push);

    always_ff @(posedge clk) begin
        if (rst) begin
            cti_baud_div_q    <= 0;
            cti_baud_cnt      <= 0;
            cti_baud_tick_16x <= 0;
        end
        else if (cti_clear || (cti_baud_div_q == 0)) begin
            cti_baud_div_q    <= baud_div;
            cti_baud_cnt      <= 0;
            cti_baud_tick_16x <= 0;
        end
        else if (cti_baud_cnt == (cti_baud_div_q - 1)) begin
            cti_baud_cnt      <= 0;
            cti_baud_tick_16x <= 1;
        end
        else begin
            cti_baud_cnt      <= cti_baud_cnt + 1;
            cti_baud_tick_16x <= 0;
        end
    end

    always_ff @(posedge clk) begin
        if (rst || cti_clear) begin
            cti_cnt <= 0;
            cti     <= 0;
        end
        else if (!cti && cti_baud_tick_16x && !rx_fifo_empty) begin
            cti_cnt <= cti_cnt + 1;

            if (cti_cnt == (timeout_ticks - 1)) begin
                cti <= 1;
            end
        end
    end

    // ================================================================
    // Interrupt Output
    // ================================================================

    logic irq_rls;
    logic irq_rda;
    logic irq_cti;
    logic irq_thre;
    logic irq_ms;

    assign irq_rls  = elsi  && (lsr_oe | lsr_pe | lsr_fe | lsr_bi);
    assign irq_rda  = erbi  && (fcr_fifo_en ? rx_fifo_trigger_met : !rx_fifo_empty);
    assign irq_cti  = erbi  && cti;
    assign irq_thre = etbei && tx_fifo_empty && !thre_ack;
    assign irq_ms   = edssi && 1'b0; // ?? UNSUPPORTED

    always_comb begin
        if      (irq_rls)  irq_id[3:0] = IIR_RLS;
        else if (irq_rda)  irq_id[3:0] = IIR_RDA;
        else if (irq_cti)  irq_id[3:0] = IIR_CTI;
        else if (irq_thre) irq_id[3:0] = IIR_THRE;
        else if (irq_ms)   irq_id[3:0] = IIR_MS;
        else               irq_id[3:0] = IIR_NO_INT;
    end

    assign irq = ~irq_id[0];
endmodule
