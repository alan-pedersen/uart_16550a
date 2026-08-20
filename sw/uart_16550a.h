#ifndef UART_16550A_H
#define UART_16550A_H

#include <stdint.h>
#include <stdbool.h>
#include <stddef.h>

#define UART_16550A_REG_DLL     0x00
#define UART_16550A_REG_DLM     0x01
#define UART_16550A_REG_RBR     0x00
#define UART_16550A_REG_THR     0x00
#define UART_16550A_REG_FCR     0x02
#define UART_16550A_REG_LCR     0x03
#define UART_16550A_REG_MCR     0x04
#define UART_16550A_REG_IER     0x01
#define UART_16550A_REG_LSR     0x05
#define UART_16550A_REG_MSR     0x06
#define UART_16550A_REG_IIR     0x02
#define UART_16550A_REG_SCR     0x07

#define UART_16550A_FCR_FIFO_EN (1U << 0)
#define UART_16550A_FCR_RX_RST  (1U << 1)
#define UART_16550A_FCR_TX_RST  (1U << 2)
#define UART_16550A_FCR_DMA     (1U << 3)
#define UART_16550A_FCR_RXTL0   (1U << 6)
#define UART_16550A_FCR_RXTL1   (1U << 7)

#define UART_16550A_LCR_WLS0    (1U << 0)
#define UART_16550A_LCR_WLS1    (1U << 1)
#define UART_16550A_LCR_STB     (1U << 2)
#define UART_16550A_LCR_PEN     (1U << 3)
#define UART_16550A_LCR_EPS     (1U << 4)
#define UART_16550A_LCR_SPS     (1U << 5)
#define UART_16550A_LCR_BC      (1U << 6)
#define UART_16550A_LCR_DLAB    (1U << 7)

#define UART_16550A_MCR_DTR     (1U << 0)
#define UART_16550A_MCR_RTS     (1U << 1)
#define UART_16550A_MCR_UT1     (1U << 2)
#define UART_16550A_MCR_OUT2    (1U << 3)
#define UART_16550A_MCR_LOOP    (1U << 4)
#define UART_16550A_MCR_AFE     (1U << 5)

#define UART_16550A_IER_ERBI    (1U << 0)
#define UART_16550A_IER_ETBEI   (1U << 1)
#define UART_16550A_IER_ELSI    (1U << 2)
#define UART_16550A_IER_EDSSI   (1U << 3)

#define UART_16550A_LSR_DR      (1U << 0)
#define UART_16550A_LSR_OE      (1U << 1)
#define UART_16550A_LSR_PE      (1U << 2)
#define UART_16550A_LSR_FE      (1U << 3)
#define UART_16550A_LSR_BI      (1U << 4)
#define UART_16550A_LSR_THRE    (1U << 5)
#define UART_16550A_LSR_TEMT    (1U << 6)
#define UART_16550A_LSR_RX_ERR  (1U << 7)

#define UART_16550A_MSR_DCTS    (1U << 0)
#define UART_16550A_MSR_DDSR    (1U << 1)
#define UART_16550A_MSR_TERI    (1U << 2)
#define UART_16550A_MSR_DDCD    (1U << 3)
#define UART_16550A_MSR_CTS     (1U << 4)
#define UART_16550A_MSR_DSR     (1U << 5)
#define UART_16550A_MSR_RI      (1U << 6)
#define UART_16550A_MSR_DCD     (1U << 7)

#define UART_16550A_IIR_IP      (1U << 0)
#define UART_16550A_IIR_ID1     (1U << 1)
#define UART_16550A_IIR_ID2     (1U << 2)
#define UART_16550A_IIR_ID3     (1U << 3)
#define UART_16550A_IIR_FIFO_EN (1U << 6)

typedef enum {
    UART_PARITY_NONE,
    UART_PARITY_ODD,
    UART_PARITY_EVEN,
    UART_PARITY_STICK
} uart_parity_t;

typedef enum {
    UART_STOP_BITS_ONE,
    UART_STOP_BITS_ONE_HALF,
    UART_STOP_BITS_TWO
} uart_stop_bits_t;

typedef enum {
    UART_OK              =  0,
    UART_ERR_INVALID_ARG = -1,
    UART_ERR_NOT_INIT    = -2,
    UART_ERR_AGAIN       = -3,
    UART_ERR_TIMEOUT     = -4,
    UART_ERR_HW_OVERRUN  = -5,
    UART_ERR_HW_PARITY   = -6,
    UART_ERR_HW_FRAME    = -7,
} uart_err_t;

typedef struct {
    uintptr_t        base_address;
    uint32_t         clock_hz;
    uint32_t         baud_rate;
    uint8_t          data_bits;
    uart_parity_t    parity;
    uart_stop_bits_t stop_bits;
    bool             enable_fifo;
    bool             enable_interrupts;
} uart_16550a_cfg_t;

typedef struct {
    uintptr_t base_address;
    uint32_t  timeout_ticks;
    bool      initialized;
} uart_16550a_t;

/**
 * @brief Initializes the UART device based on the provided configuration.
 * 
 * @param dev Pointer to the device instance to initialize.
 * @param cfg Pointer to the configuration struct.
 * 
 * @return UART_OK on success, UART_ERR_INVALID_ARG if parameters are invalid.
 */
int uart_16550a_init(uart_16550a_t* dev, const uart_16550a_cfg_t* cfg);

/**
 * @brief Resets the UART hardware by flushing FIFOs and resetting registers.
 * 
 * @param dev Pointer to the device instance.
 * 
 * @return UART_OK on success, UART_ERR_NOT_INIT if device is invalid.
 */
int uart_16550a_rst(uart_16550a_t* dev);

/**
 * @brief Attempts to transmit a single character without blocking.
 * 
 * @param dev Pointer to the device instance.
 * @param c   Character to transmit.
 * 
 * @return UART_OK if transmitted, UART_ERR_AGAIN if TX FIFO is full.
 */
int uart_16550a_putc(uart_16550a_t* dev, char c);

/**
 * @brief Attempts to receive a single character without blocking.
 * 
 * @param dev Pointer to the device instance.
 * @param c   Pointer to store the received character.
 * 
 * @return UART_OK if character received, UART_ERR_AGAIN if RX FIFO
 *         is empty, or a hardware error code (e.g., UART_ERR_HW_PARITY).
 */
int uart_16550a_getc(uart_16550a_t* dev, char* c);

/**
 * @brief Transmits a buffer of bytes while blocking.
 * 
 * @param dev  Pointer to the device instance.
 * @param data Buffer containing bytes to transmit.
 * @param len  Number of bytes to transmit.
 * 
 * @return The number of bytes successfully transmitted, or a negative
 *         error code (e.g., UART_ERR_TIMEOUT).
 */
int uart_16550a_write(uart_16550a_t* dev, const uint8_t* data, size_t len);

/**
 * @brief Reads a specified number of bytes into a buffer while blocking.
 * 
 * @param dev    Pointer to the device instance.
 * @param buffer Pointer to the buffer in which to store the received data.
 * @param len    Maximum number of bytes to read.
 * 
 * @return The number of bytes successfully received, or a negative error
 *         code (e.g., UART_ERR_TIMEOUT).
 */
int uart_16550a_read(uart_16550a_t* dev, uint8_t* buffer, size_t len);

#endif
