# order-send-slave
MQL5 library allowing slave EAs to register and receive updates from a master EA with which they're connected

## Installation
To install this library, simply clone the repository to your `/MQL5/Include` directory, for MT5, or your `/MQL4/Include` directory for MT4. Once you've done that, install the [Json package](https://github.com/xefino/mql5-json), which this library depends on, to the same directory. Finally, insert the following statement into the top of every MQL5 file you want to use:

```
#include <order-send-slave/Slave_5.mqh>
```

For MQL4, you can do the following import instead:

```
#include <order-send-slave/Slave_4.mqh>
```
