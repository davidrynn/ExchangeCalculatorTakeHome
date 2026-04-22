#  Code Challenge Instructions

Assignment
Mobile Engineering Home Task

Overview

Build a currency exchange rate calculator app for native Android or iOS. This task should take approximately 10-15 hours to complete. You have 1 week from receiving this task to submit your solution. Even if this is a small mobile app, it should be a showcase of your skills and experience.


Functional Requirements


Core Features

Build an exchange rate calculator that converts between USDc and other currencies with the following functionality:

1. Currency Input Fields

   - Two input fields: one for USDc and one for the selected currency

   - Users should be able to enter amounts in either field

   - The app should automatically calculate and update the corresponding amount in the other field

2. Currency Selection

   - Tapping the non-USDc currency should open a bottom sheet where users can select a different currency

3. Currency Swap

   - Include a swap button (arrow) between the two currency fields

   - Tapping this button should swap the positions of the two currencies

4. Working Application

   - The app must be fully functional and demonstrate all the features listed above



Technical Requirements
User Experience

- The application should provide a good user experience

- Consider edge cases and how users will interact with the app

- Feel free to use system default font instead of the custom specified in the designs.


APIs

You will use the following APIs to fetch exchange rates against USDc:

Exchange Rate API

GET: https://api.dolarapp.dev/v1/tickers?currencies=MXN,ARS

[

  {

    "ask": "18.4105000000",

    "bid": "18.4069700000",

    "book": "usdc_mxn",

    "date": "2025-10-20T20:14:57.361483956"

  },

  {

    "ask": "1551.0000000000",

    "bid": "1539.4290300000",

    "book": "usdc_ars",

    "date": "2025-10-21T09:44:18.512194175"

  }

]

List of Available Currencies API

Note: This API is not yet available. You can expect it to have the following structure when implemented:


GET: https://api.dolarapp.dev/v1/tickers-currencies

[

  "MXN",

  "ARS",

  "BRL",

  "COP"

]


The app must be fully functional despite this API not being available yet. Handle this scenario appropriately.


UI Reference

Link to the the Figma design document

https://www.figma.com/design/xX7gSbMEIzybCrG9Wwk9Wx/-EXT--Exchange-Home-Task?node-id=0-1&t=PPlbFi36Kl74CHg0-1

Password: DolarApp!123

You can log in or create an account to have access to development properties like sizes and margins.


Submission

A link to a git repository where the solution is available and we should be able to open and run the app in the simulator without any modifications.
