#[starknet::contract]
pub mod Margin {
    use openzeppelin_token::erc20::interface::IERC20DispatcherTrait;
    use core::num::traits::Zero;
    use starknet::{
        event::EventEmitter,
        storage::{StoragePointerReadAccess, StoragePointerWriteAccess, StoragePathEntry, Map},
        ContractAddress, get_contract_address, get_caller_address,
    };
    use margin::{interface::IMargin, types::{Position, TokenAmount, PositionParameters}};
    use openzeppelin_token::erc20::interface::{IERC20Dispatcher};

    #[derive(starknet::Event, Drop)]
    struct Deposit {
        depositor: ContractAddress,
        token: ContractAddress,
        amount: TokenAmount,
    }

    #[derive(starknet::Event, Drop)]
    struct Withdraw {
        withdrawer: ContractAddress,
        token: ContractAddress,
        amount: TokenAmount,
    }


    #[event]
    #[derive(Drop, starknet::Event)]
    enum Event {
        Deposit: Deposit,
        Withdraw: Withdraw,
    }

    #[storage]
    struct Storage {
        treasury_balances: Map<(ContractAddress, ContractAddress), TokenAmount>,
        pools: Map<ContractAddress, TokenAmount>,
        positions: Map<ContractAddress, Position>,
    }

    #[abi(embed_v0)]
    impl Margin of IMargin<ContractState> {
        /// Deposits specified amount of ERC20 tokens into the contract's treasury
        /// @param token The contract address of the ERC20 token to deposit
        /// @param amount The amount of tokens to deposit
        /// @dev Transfers tokens from caller to contract and updates balances
        fn deposit(ref self: ContractState, token: ContractAddress, amount: TokenAmount) {
            assert(amount.is_non_zero(), 'Amount is zero');
            let token_dispatcher = IERC20Dispatcher { contract_address: token };
            let (depositor, contract) = (get_caller_address(), get_contract_address());

            assert(
                token_dispatcher.allowance(depositor, contract) >= amount, 'Insufficient allowance',
            );
            assert(token_dispatcher.balance_of(depositor) >= amount, 'Insufficient balance');

            let user_balance = self.treasury_balances.entry((depositor, token)).read();
            self.treasury_balances.entry((depositor, token)).write(user_balance + amount);

            let pool_value = self.pools.entry(token).read();
            self.pools.entry(token).write(pool_value + amount);

            token_dispatcher.transfer_from(depositor, contract, amount);

            self.emit(Deposit { depositor, token, amount });
        }

        fn withdraw(ref self: ContractState, token: ContractAddress, amount: TokenAmount) {
            assert(amount > 0, 'Withdraw amount is zero');

            let withdrawer = get_caller_address();

            let user_treasury_amount = self.treasury_balances.entry((withdrawer, token)).read();
            assert(amount <= user_treasury_amount, 'Insufficient user treasury');

            self.treasury_balances.entry((withdrawer, token)).write(user_treasury_amount - amount);

            let token_dispatcher = IERC20Dispatcher { contract_address: token };
            token_dispatcher.transfer(withdrawer, amount);

            let pool_value = self.pools.entry(token).read();
            self.pools.entry(token).write(pool_value - amount);

            self.emit(Withdraw { withdrawer, token, amount });
        }

        // TODO: Add Ekubo data for swap
        fn open_margin_position(ref self: ContractState, position_parameters: PositionParameters) {}
        fn close_position(ref self: ContractState) {}
        fn liquidate(ref self: ContractState, user: ContractAddress) {}
    }
}
