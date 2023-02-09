# order-send-slave
This library contains MT4 and MT5 Expert Advisors to receive orders from a master Expert Advisors to which it is connected. This code works by registering the IP address and port of the expert advisor with the web server, and then opening a socket to receive trade requests sent from the server.

## Installation
To install this expert, simply clone the repository to your `/MQL5/Experts` directory, for MT5, or your `/MQL4/Experts` directory for MT4. Once you've done that, install the [Json package](https://github.com/xefino/mql5-json), which this library depends on, to the same directory. For MQL4, you'll also need to install the [order-send-common-mt4 package](https://github.com/xefino/order-send-common-mt4).

### MetaTrader 4 Settings
Before running the expert, you must ensure that your instance of MetaTrader 4 is configured properly. This expert makes use of web requests to register the slave EA so it can receive and then makes use of an internal sockets library to receive orders sent from the server. Therefore, web requests need to be enabled to two URLs from the table in the [URLs section](#urls): one for registration and one for receipt. Moreover, algorithmic trading and DLL imports need to be enabled. Failing to do so will result in slave registration returning a 4014 error and/or failure of the slave expert to receive any orders. To do this, simply execute the following steps:

1. Open your instance of MetaTrader 4.
2. Navigate to the top menu bar and click on `Tools`. Then scroll down and click on `Options`:

![Finding the Options Menu](https://github.com/xefino/order-send-slave/blob/main/docs/select%20screen%204.png)
 
3. In the `Options` window, select the `Expert Advisors` pane and ensure that the `Allow automated trading`, `All DLL imports` and `Allow WebRequest for listed URL:` options are selected.
4. Copy the URL which should be used to register the slave EA. Then, in the list of allowed URLs, click the `+` icon and paste the URL into the resulting text box. Repeat this for the desired receipt URL.
 
![Updating the allowed URLs](https://github.com/xefino/order-send-slave/blob/main/docs/options%20screen%204.png)

 5. Click Ok to save your settings.

### MetaTrader 5 Settings
Before running the expert, you must ensure that your instance of MetaTrader 5 is configured properly. This expert makes use of web requests to register the slave EA so it can receive and then makes use of an internal sockets library to receive orders sent from the server. Therefore, web requests need to be enabled to two URLs from the table in the [URLs section](#urls): one for registration and one for receipt. Moreover, algorithmic trading needs to be enabled. Failing to do so will result in slave registration returning a 4014 error and/or failure of the slave expert to receive any orders. To do this, simply execute the following steps:

1. Open your instance of MetaTrader 5.
2. Navigate to the top menu bar and click on `Tools`. Then scroll down and click on `Options`:

![Finding the Options Menu](https://github.com/xefino/order-send-slave/blob/main/docs/select%20screen%205.png)
 
3. In the `Options` window, select the `Expert Advisors` pane and ensure that the `Allow automated trading` and `Allow WebRequest for listed URL:` options are selected.
4. Copy the URL which should be used to register the slave EA. Then, in the list of allowed URLs, click the `+` icon and paste the URL into the resulting text box. Repeat this for the desired receipt URL.
 
![Updating the allowed URLs](https://github.com/xefino/order-send-slave/blob/main/docs/options%20screen%205.png)

 5. Click Ok to save your settings.

### URLs
This section contains a list of URLs which need to be enabled on the slave EA, the environment to which they will connect and their purpose.

| Environment | Purpose      | URL |
| ----------- | ------------ | --- |
| Test        | Registration | https://qh7g3o0ypc.execute-api.ap-northeast-1.amazonaws.com/register |
| Test        | Receipt      | https://uzttwvn3enog6rsbszftsdn5cq0nkoyg.lambda-url.ap-northeast-1.on.aws/ |
| Production  | Registration | https://rurdtoe916.execute-api.ap-southeast-1.amazonaws.com/register |
| Production  | Receipt      | https://5fvke4cgomxsg7mvrfdf6f6oge0lsygw.lambda-url.ap-southeast-1.on.aws/ |

### Opening the Receipt Port
One last thing that needs to be done before running the EA is to ensure that the port which you plan to use to receive orders is open. This is very important as MetaTrader is not capable of opening ports on its own, and giving it that capability would be a major security risk. Therefore, the user needs to ensure that the port is open properly. This section can serve as a guide for doing so.

1. Choose a port number. In general, this should be a four- or five-digit number not less than 1024 and should not be 80 or 443 as those are reserved for HTTP and HTTPS requests. Good examples would include 8000, 8080, 9000, etc. You can choose any value you prefer so long as it isn't reserved for anything else. For a list of commonly used port numbers, please refer to [this article](https://en.wikipedia.org//wiki/List_of_TCP_and_UDP_port_numbers).
2. Open the control panel. This screen may look different depending on your operating system, but if you have Windows 7/8/10/11 then the screen will have a format similar to this.

![Control Panel](https://github.com/xefino/order-send-slave/blob/main/docs/control%20panel.png)

3. Navigate to the Windows Firewall settings. For Windows 7 or later, this will be called Windows Defender. For Windows XP, it may be called Windows Firewall.

![Security & Firewall Setttings](https://github.com/xefino/order-send-slave/blob/main/docs/security.png)

4. On the side menu, there should be an option labelled `Advanced settings`. Click on this to open up the advanced firewall settings menu.

![Advanced Firewall Settings](https://github.com/xefino/order-send-slave/blob/main/docs/advanced.png)

5. At this point, you will need to create an inbound rule and an outbound rule allowing traffic through the port you chose. So you'll repeat this step and all the following steps for each. Click on the appropriate rule type (`Inbound Rules` and `Outbound Rules`) and then select the `New Rule...` option.

![New Rule Dialog](https://github.com/xefino/order-send-slave/blob/main/docs/newrule.png)

6. In the New Rule dialog, select the `Port` option and click `Next`.
7. On the next page, ensure TCP is selected for the protocol type and ensure that the `Specific local ports` option is selected. It is not recommended to open all ports as this rule is not tied to a specific program or URL. If you want to run multiple slave EAs on the same machine, you can enter multiple port numbers separated by commas or open a range of ports. **Note that each slave EA must have its own, dedicated port.**. Once you've chosen your port(s), click `Next`.

![Port Selection Page](https://github.com/xefino/order-send-slave/blob/main/docs/port%20choice.png)

8. On the next page, ensure that `Allow the connection` is selected and click `Next`.

![Connection Page](https://github.com/xefino/order-send-slave/blob/main/docs/allow.png)

9. Now, we need to ensure when the rule applies. What you select here will depend on where the master is located and the type of network. If you're not sure, leave all options checked. Click `Next`.

![Rule Page](https://github.com/xefino/order-send-slave/blob/main/docs/conditions.png)

10. Finally, we need to decide on a name for the rule. This guide has named the rule `Slave EA` but you can choose whatever you want for a name, so long as it is memorable to you. You may also add a description for the rule at this time. Once you've done that, click `Finish` and the rule will be complete.

![Naming Page](https://github.com/xefino/order-send-slave/blob/main/docs/namerule.png)

## Running the Expert
To run the expert, you open a new chart for any symbol and add the expert to it, by double-clicking on it in the Navigator list or dragging it onto the chart. The expert will be named "Slave_4" or "Slave_5" for MetaTrader 4 and MetaTrader 5, respectively You do not need to run multiple copies of the EA on charts for each symbol which you trade. You should only run one copy of the receiver EA, on any chart. This will attempt to submit a copy of each order it receives from the master EA to the trade server.

### Settings
This section explains the settings associated with the master.

#### Environment
The environment to run the master in. There are two values for this: `Test` and `Production`. Test is intended to demonstrate new features but, for actual trading, `Production` should be used. This value will be used to determine which URL the EA uses for registration and receipt of orders.

#### Port
The port number that this EA should expect to receive orders on. See the [Opening the Receipt Port](#opening-the-receipt-port) section for more information.

#### Password
The web server requires authentication before it can be accessed. Therefore, the password parameter must be set or all attempts to send orders will fail with a 403 error. The password is not included in this guide. You may request it to be sent to you.

#### Save File Name
The name of the file to which orders data should be saved. See the [Mapping Orders](#mapping-orders) section for more information.

#### Magic Number
The magic number to use when sending copied orders to the broker. This value should be unique with respect to all the EAs running on your instance of MT4 or MT5.

#### Arrow Color
The color of the arrow to use when the trades the EA makes are written to the chart. This value does not need to be set, but is provided for your convenience.

#### Slippage (Pts)
The number of points to allow in slippage. This parameter has been included because slippage is not retrievable once an order has been submitted, so we have no way of determining what slippage value the master EA used to generate the original trade. Set this to whatever value you prefer.

## Operation
In general, the slave expert waits to receive orders from the master expert. The slave EA will then attempt to place the same trade. Transmission is subject to lag but all server resources are located in Singapore in an effort to reduce latency. The time taken to transmit the trade should be no more than three seconds but the actual copy time will also depend on the ability of your broker(s) to handle the copied trade. The data transmitted will depend on the version of MetaTrader you're using and your master and slave must be using the same version of MetaTrader for the transmission to work. Note that if submission of an order fails, for any reason, then the order will not be re-submitted. Further note that the Market Watch must contain all the symbols which are going to be traded. In  addition, if the receiving MT4 account should be in the same currency as the sending account. For example, if the senders’s deposit currency is GBP or JPY, then the receiver's deposit currency must also be GBP or JPY, respectively. Finally, the user should be aware that the slave EA will not copy any orders that were posted before it was started.

## Mapping Orders
In order to handle order updates or deletes, the slave EA requires the ability to map order ticket numbers on the master EA to ticket numbers of copied orders. As a part of this functionality, the slave EA will save a copy of this mapping to a file before it is removed, and will attempt to read a file of the same name when it starts up. This file name can be changed by setting the `Save File Name` parameter. Note, that changing this value will cause the slave EA to "forget" the old file. So, the user should change the name of this file manually before attmepting to change this parameter. The save file can be located in the MetaTrader common directory, `\Terminal\Common\Files`.

## Handling Disconnects
The slave expert will listen continuously until it receives order data from the master. Should the connection fail, the error will be logged and the connection will be attempted next tick. Therefore, the slave expert exhibits an ability to recover from network issues quickly. That being said, if network issues are prolonged then the expert may still fail to retrieve order data. In this case, such orders will be ignored.

### MetaTrader 4 Transmission
Due to limitations of MQL4, the master will be unable to transmit close-by orders as we have no way of retrieving the position-by data from the order at this time. Therefore, we will only be able to handle a subset of potential trade operations.

### MetaTrader 5 Transmission
In MQL5 we have access to the `MqlTradeRequest` object, which contains all data needed to create an order. This information is serialized directly so the order can be recreated exactly on the slave. Therefore, all order types can be copied.
