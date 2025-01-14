// [!region contract]
pub use starknet::{ContractAddress, ClassHash};

#[starknet::interface]
pub trait ICampaignFactory<TContractState> {
    fn create_campaign(
        ref self: TContractState,
        title: ByteArray,
        description: ByteArray,
        goal: u256,
        start_time: u64,
        end_time: u64,
        token_address: ContractAddress
    ) -> ContractAddress;
    fn get_campaign_class_hash(self: @TContractState) -> ClassHash;
    fn update_campaign_class_hash(ref self: TContractState, new_class_hash: ClassHash);
    fn upgrade_campaign(
        ref self: TContractState, campaign_address: ContractAddress, new_end_time: Option<u64>
    );
}

#[starknet::contract]
pub mod CampaignFactory {
    use core::num::traits::Zero;
    use starknet::{
        ContractAddress, ClassHash, SyscallResultTrait, syscalls::deploy_syscall, get_caller_address
    };
    use crowdfunding::campaign::{ICampaignDispatcher, ICampaignDispatcherTrait};
    use components::ownable::ownable_component;
    use starknet::storage::{
        Map, StorageMapReadAccess, StorageMapWriteAccess, StoragePointerReadAccess,
        StoragePointerWriteAccess
    };

    component!(path: ownable_component, storage: ownable, event: OwnableEvent);

    #[abi(embed_v0)]
    impl OwnableImpl = ownable_component::Ownable<ContractState>;
    impl OwnableInternalImpl = ownable_component::OwnableInternalImpl<ContractState>;

    #[storage]
    struct Storage {
        #[substorage(v0)]
        ownable: ownable_component::Storage,
        /// Store all of the created campaign instances' addresses and their class hashes
        campaigns: Map<(ContractAddress, ContractAddress), ClassHash>,
        /// Store the class hash of the contract to deploy
        campaign_class_hash: ClassHash,
    }

    #[event]
    #[derive(Drop, starknet::Event)]
    pub enum Event {
        #[flat]
        OwnableEvent: ownable_component::Event,
        CampaignClassHashUpgraded: CampaignClassHashUpgraded,
        CampaignCreated: CampaignCreated,
        ClassHashUpdated: ClassHashUpdated,
    }

    #[derive(Drop, starknet::Event)]
    pub struct ClassHashUpdated {
        pub new_class_hash: ClassHash,
    }

    #[derive(Drop, starknet::Event)]
    pub struct CampaignClassHashUpgraded {
        pub campaign: ContractAddress,
    }

    #[derive(Drop, starknet::Event)]
    pub struct CampaignCreated {
        pub creator: ContractAddress,
        pub contract_address: ContractAddress
    }

    pub mod Errors {
        pub const CLASS_HASH_ZERO: felt252 = 'Class hash cannot be zero';
        pub const ZERO_ADDRESS: felt252 = 'Zero address';
        pub const SAME_IMPLEMENTATION: felt252 = 'Implementation is unchanged';
        pub const CAMPAIGN_NOT_FOUND: felt252 = 'Campaign not found';
    }

    #[constructor]
    fn constructor(ref self: ContractState, class_hash: ClassHash) {
        assert(class_hash.is_non_zero(), Errors::CLASS_HASH_ZERO);
        self.campaign_class_hash.write(class_hash);
        self.ownable._init(get_caller_address());
    }


    #[abi(embed_v0)]
    impl CampaignFactory of super::ICampaignFactory<ContractState> {
        fn create_campaign(
            ref self: ContractState,
            title: ByteArray,
            description: ByteArray,
            goal: u256,
            start_time: u64,
            end_time: u64,
            token_address: ContractAddress,
        ) -> ContractAddress {
            let creator = get_caller_address();

            // Create constructor arguments
            let mut constructor_calldata: Array::<felt252> = array![];
            ((creator, title, description, goal), start_time, end_time, token_address)
                .serialize(ref constructor_calldata);

            // Contract deployment
            let (contract_address, _) = deploy_syscall(
                self.campaign_class_hash.read(), 0, constructor_calldata.span(), false
            )
                .unwrap_syscall();

            // track new campaign instance
            self.campaigns.write((creator, contract_address), self.campaign_class_hash.read());

            self.emit(Event::CampaignCreated(CampaignCreated { creator, contract_address }));

            contract_address
        }

        fn get_campaign_class_hash(self: @ContractState) -> ClassHash {
            self.campaign_class_hash.read()
        }

        fn update_campaign_class_hash(ref self: ContractState, new_class_hash: ClassHash) {
            self.ownable._assert_only_owner();
            assert(new_class_hash.is_non_zero(), Errors::CLASS_HASH_ZERO);

            self.campaign_class_hash.write(new_class_hash);

            self.emit(Event::ClassHashUpdated(ClassHashUpdated { new_class_hash }));
        }

        fn upgrade_campaign(
            ref self: ContractState, campaign_address: ContractAddress, new_end_time: Option<u64>
        ) {
            assert(campaign_address.is_non_zero(), Errors::ZERO_ADDRESS);

            let creator = get_caller_address();
            let old_class_hash = self.campaigns.read((creator, campaign_address));
            assert(old_class_hash.is_non_zero(), Errors::CAMPAIGN_NOT_FOUND);
            assert(old_class_hash != self.campaign_class_hash.read(), Errors::SAME_IMPLEMENTATION);

            let campaign = ICampaignDispatcher { contract_address: campaign_address };
            campaign.upgrade(self.campaign_class_hash.read(), new_end_time);
        }
    }
}
// [!endregion contract]


