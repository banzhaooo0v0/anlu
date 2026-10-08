#include "uartx.h"
typedef char tx_pin_is_pd8[(UART3_TX_PIN == GPIO_Pin_8) ? 1 : -1];
typedef char rx_pin_is_pd9[(UART3_RX_PIN == GPIO_Pin_9) ? 1 : -1];
typedef char tx_af_source_is_8[(UART3_TX_Soure == GPIO_PinSource8) ? 1 : -1];
typedef char rx_af_source_is_9[(UART3_RX_Soure == GPIO_PinSource9) ? 1 : -1];
GPIO_TypeDef *contract_tx_port(void) { return UART3_TX_PORT; }
GPIO_TypeDef *contract_rx_port(void) { return UART3_RX_PORT; }
GPIO_TypeDef *contract_expected_port(void) { return GPIOD; }
