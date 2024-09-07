// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

///@notice This cheat codes interface is named _CheatCodes so you can use the CheatCodes interface in other testing files without errors
interface _CheatCodes {
    function ffi(string[] calldata) external returns (bytes memory);
}

contract VyperDeployer {
    address constant HEVM_ADDRESS =
        address(bytes20(uint160(uint256(keccak256("hevm cheat code")))));

    /// @notice Initializes cheat codes in order to use ffi to compile Vyper contracts
    _CheatCodes cheatCodes = _CheatCodes(HEVM_ADDRESS);

    ///@notice Compiles a Vyper contract and returns the address that the contract was deployeod to
    ///@notice If deployment fails, an error will be thrown
    ///@param filePath - The file path of the Vyper contract.
    ///@return deployedAddress - The address that the contract was deployed to

    function deployContract(string memory filePath) public returns (address) {
        ///@notice create a list of strings with the commands necessary to compile Vyper contracts
        string[] memory cmds = new string[](2);
        cmds[0] = "vyper";
        cmds[1] = filePath;

        ///@notice compile the Vyper contract and return the bytecode
        bytes memory bytecode = cheatCodes.ffi(cmds);

        ///@notice deploy the bytecode with the create instruction
        address deployedAddress;
        assembly {
            deployedAddress := create(0, add(bytecode, 0x20), mload(bytecode))
        }

        ///@notice check that the deployment was successful
        require(
            deployedAddress != address(0),
            "VyperDeployer could not deploy contract"
        );

        ///@notice return the address that the contract was deployed to
        return deployedAddress;
    }

    ///@notice Compiles a Vyper contract with constructor arguments and returns the address that the contract was deployeod to
    ///@notice If deployment fails, an error will be thrown
    ///@param filePath - The file path of the Vyper contract.
    ///@return deployedAddress - The address that the contract was deployed to
    function deployContract(
        string memory filePath,
        bytes memory args
    ) public returns (address) {
        ///@notice create a list of strings with the commands necessary to compile Vyper contracts
        string[] memory cmds = new string[](2);
        cmds[0] = "vyper";
        cmds[1] = filePath;

        ///@notice compile the Vyper contract and return the bytecode
        bytes memory _bytecode = cheatCodes.ffi(cmds);

        //add args to the deployment bytecode
        bytes memory bytecode = abi.encodePacked(_bytecode, args);

        ///@notice deploy the bytecode with the create instruction
        address deployedAddress;
        assembly {
            deployedAddress := create(0, add(bytecode, 0x20), mload(bytecode))
        }

        ///@notice check that the deployment was successful
        require(
            deployedAddress != address(0),
            "VyperDeployer could not deploy contract"
        );

        ///@notice return the address that the contract was deployed to
        return deployedAddress;
    }

    /// @dev Consider listening to the Blueprint if you haven't already
    /// @param filePath - The file path of the Blueprint Contract
    function deployBlueprint(string memory filePath) public returns (address) {
        ///@notice create a list of strings with the commands necessary to compile Vyper contracts
        string[] memory cmds = new string[](2);
        cmds[0] = "vyper";
        cmds[1] = filePath;

        ///@notice compile the Vyper contract and return the bytecode
        bytes memory bytecode = cheatCodes.ffi(cmds);

        require(bytecode.length > 0, "Initcodes length must be greater than 0");

        /// @notice prepend needed items for Blueprint ERC
        /// See https://eips.ethereum.org/EIPS/eip-5202 for more details
        bytes memory eip_5202_bytecode = bytes.concat(
            hex"fe", // EIP_5202_EXECUTION_HALT_BYTE
            hex"71", // EIP_5202_BLUEPRINT_IDENTIFIER_BYTE
            hex"00", // EIP_5202_VERSION_BYTE
            bytecode
        );

        bytes2 len = bytes2(uint16(eip_5202_bytecode.length));

        /// @notice prepend the deploy preamble
        bytes memory deployBytecode = bytes.concat(
            hex"61", // DEPLOY_PREAMBLE_INITIAL_BYTE
            len, // DEPLOY_PREAMBLE_BYTE_LENGTH
            hex"3d81600a3d39f3", // DEPLOY_PREABLE_POST_LENGTH_BYTES
            eip_5202_bytecode
        );

        ///@notice check that the deployment was successful
        address deployedAddress;
        assembly {
            deployedAddress := create(
                0,
                add(deployBytecode, 0x20),
                mload(deployBytecode)
            )
        }

        require(
            deployedAddress != address(0),
            "VyperDeployer could not deploy contract"
        );

        ///@notice return the address that the contract was deployed to
        return deployedAddress;
    }
}
