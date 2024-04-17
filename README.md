# USDC PSM sDAI Strategy for yearn V3

yearn v3 strategy that trade USDC through PSM and farms sDAI.

### Requirements

First you will need to install [Foundry](https://book.getfoundry.sh/getting-started/installation).
NOTE: If you are on a windows machine it is recommended to use [WSL](https://learn.microsoft.com/en-us/windows/wsl/install)

### Set your environment Variables

Sign up for [Infura](https://infura.io/) and generate an API key and copy your RPC url. Store it in the `ETH_RPC_URL` environment variable.
NOTE: you can use other services.

Use .env file

1. Make a copy of `.env.example`
2. Add the values for `POLYGON_RPC_URL`, `POLYGON_API_KEY` and other example vars
     NOTE: If you set up a global environment variable, that will take precedence.

### Build the project

```sh
make build
```

Run tests

```sh
make test
```