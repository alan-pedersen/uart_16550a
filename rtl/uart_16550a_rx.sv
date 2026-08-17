module uart_16550a_rx (
    input  logic        clk,
    input  logic        rst,
    input  logic [15:0] baud_div,
    input  logic        rx,
    output logic [7:0]  rx_data,
    output logic        rx_valid,
    output logic        rx_pe,
    output logic        rx_fe,
    output logic        rx_bi,

    input  logic [1:0]  lcr_word_len,
    input  logic        lcr_parity_en,
    input  logic        lcr_parity_even,
    input  logic        lcr_parity_stick
);
    import uart_16550a_pkg::*;

    typedef enum logic [2:0] {
        ST_IDLE   = 3'd0,
        ST_START  = 3'd1,
        ST_DATA   = 3'd2,
        ST_PARITY = 3'd3,
        ST_STOP   = 3'd4
    } state_t;

    state_t state;

    // ================================================================
    // RX Synchronization
    // ================================================================

    logic       rx_meta;
    logic       rx_sync;
    logic       rx_prev;
    logic [1:0] rx_history;
    logic       rx_vote;

    always_ff @(posedge clk) begin
        if (rst) begin
            rx_meta    <= 1;
            rx_sync    <= 1;
            rx_prev    <= 1;
            rx_history <= 2'b11;
        end
        else begin
            rx_meta <= rx;
            rx_sync <= rx_meta;
            rx_prev <= rx_sync;

            if (baud_tick_16x) begin
                rx_history <= {rx_history[0], rx_sync};
            end
        end
    end

    assign rx_vote = (rx_history[1] & rx_history[0]) |
                     (rx_history[1] & rx_sync)       |
                     (rx_history[0] & rx_sync);

    // ================================================================
    // Control Signals
    // ================================================================

    // These signals are derived purely for readability.
    // The logic could be written inline without changing functionality

    logic rx_ready; // Indicates that the FSM is in ST_IDLE and ready to start receiving
    logic rx_start; // Indicates a falling edge on RX; not necessarily a valid start bit

    assign rx_ready = (state == ST_IDLE);
    assign rx_start = (rx_sync == 0) && (rx_prev == 1);

    // ================================================================
    // Baud Generation
    // ================================================================

    logic [15:0] baud_div_q;
    logic [15:0] baud_counter;
    logic        baud_tick_16x;

    // Shadow the baud divisor so DLL/DLM writes cannot
    // corrupt a reception already in progress
    always_ff @(posedge clk) begin
        if (rst) begin
            baud_div_q <= 0;
        end
        else if (rx_ready && rx_start) begin
            baud_div_q <= baud_div;
        end
    end

    // Keep the baud counter inactive while the FSM is idle
    // or when the baud divisor is zero
    always_ff @(posedge clk) begin
        if (rst || (state == ST_IDLE) || (baud_div_q == 0)) begin
            baud_counter  <= 0;
            baud_tick_16x <= 0;
        end
        else if (baud_counter == (baud_div_q - 1)) begin
            baud_counter  <= 0;
            baud_tick_16x <= 1;
        end
        else begin
            baud_counter  <= baud_counter + 1;
            baud_tick_16x <= 0;
        end
    end

    // ================================================================
    // RX Control
    // ================================================================

    // Shadow the LCR fields to prevent
    // changes mid-reception
    logic [1:0] lcr_word_len_q;
    logic       lcr_parity_en_q;
    logic       lcr_parity_even_q;
    logic       lcr_parity_stick_q;

    logic [7:0] rsr;
    logic [3:0] max_bits; // Word length minus 1; extra bit allows comparison with bit_cnt
    logic [3:0] bit_cnt;  // Extra bit allows the count to reach 8 (not just 7)
    logic [3:0] counter;  // Counts baud ticks within a bit (16 ticks per bit)

    logic       parity_expected;
    logic       parity_received;

    logic       is_zero_data;
    logic       is_zero_parity;
    logic       break_condition;

    logic       midpoint_pe;
    logic       midpoint_fe;
    logic       midpoint_bi;

    assign is_zero_data    = (rsr == 8'd0);
    assign is_zero_parity  = (!lcr_parity_en_q || (parity_received == 1'b0));
    assign break_condition = is_zero_data && is_zero_parity;

    always_ff @(posedge clk) begin
        if (rst) begin
            lcr_word_len_q     <= 0;
            lcr_parity_en_q    <= 0;
            lcr_parity_even_q  <= 0;
            lcr_parity_stick_q <= 0;
            rsr                <= 0;
            max_bits           <= 0;
            bit_cnt            <= 0;
            counter            <= 0;
            parity_expected    <= 0;
            parity_received    <= 0;
            midpoint_pe        <= 0;
            midpoint_fe        <= 0;
            midpoint_bi        <= 0;
            rx_data            <= 0;
            rx_valid           <= 0;
            rx_pe              <= 0;
            rx_fe              <= 0;
            rx_bi              <= 0;
            state              <= ST_IDLE;
        end
        else begin
            rx_valid <= 0;
            rx_pe    <= 0;
            rx_fe    <= 0;
            rx_bi    <= 0;

            unique case (state)
                ST_IDLE: begin
                    if (rx_start) begin
                        lcr_word_len_q     <= lcr_word_len;
                        lcr_parity_en_q    <= lcr_parity_en;
                        lcr_parity_even_q  <= lcr_parity_even;
                        lcr_parity_stick_q <= lcr_parity_stick;
                        rsr                <= 0;
                        max_bits           <= 4 + {2'b00, lcr_word_len};
                        bit_cnt            <= 0;
                        counter            <= 0;
                        midpoint_pe        <= 0;
                        midpoint_fe        <= 0;
                        midpoint_bi        <= 0;
                        state              <= ST_START;
                    end
                end
                ST_START: begin
                    if (baud_tick_16x) begin
                        if (counter == 15) begin
                            counter <= 0;
                            state   <= ST_DATA;
                        end
                        else begin
                            counter <= counter + 1;

                            if ((counter == 9) && (rx_vote != 0)) begin
                                state <= ST_IDLE;
                            end
                        end
                    end
                end
                ST_DATA: begin
                    if (baud_tick_16x) begin
                        if (counter == 15) begin
                            counter <= 0;

                            // Use '>' because bit_cnt is incremented before reaching this check
                            if (bit_cnt > max_bits) begin
                                parity_expected <= calc_parity(rsr, lcr_word_len_q, lcr_parity_even_q, lcr_parity_stick_q);
                                state           <= lcr_parity_en_q ? ST_PARITY : ST_STOP;
                            end
                        end
                        else begin
                            counter <= counter + 1;

                            if (counter == 9) begin
                                rsr[bit_cnt[2:0]] <= rx_vote;
                                bit_cnt           <= bit_cnt + 1;
                            end
                        end
                    end
                end
                ST_PARITY: begin
                    if (baud_tick_16x) begin
                        if (counter == 15) begin
                            counter <= 0;
                            state   <= ST_STOP;
                        end
                        else begin
                            counter <= counter + 1;

                            if (counter == 9) begin
                                parity_received <= rx_vote;

                                if (rx_vote != parity_expected) begin
                                    midpoint_pe <= 1;
                                end
                            end
                        end
                    end
                end
                ST_STOP: begin
                    if (baud_tick_16x) begin
                        if (counter == 10) begin
                            counter  <= 0;
                            rx_valid <= 1;
                            rx_data  <= rsr;
                            rx_pe    <= midpoint_pe;
                            rx_fe    <= midpoint_fe;
                            rx_bi    <= midpoint_bi;
                            state    <= ST_IDLE;
                        end
                        else begin
                            counter <= counter + 1;

                            if (counter == 9) begin
                                if (rx_vote != 1) begin
                                    midpoint_fe <= 1;

                                    if (break_condition) begin
                                        midpoint_bi <= 1;
                                    end
                                end
                            end
                        end
                    end
                end
            endcase
        end
    end
endmodule
