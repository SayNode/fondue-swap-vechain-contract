// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.14;

import "@openzeppelin/contracts/token/ERC721/ERC721.sol";
import "./HelpFunctions.sol";

import "./interfaces/IERC20.sol";
import "./interfaces/IUniswapV3Pool.sol";
import "./lib/LiquidityMath.sol";
import "./lib/NFTRenderer.sol";
import "./lib/PoolAddress.sol";
import "./lib/TickMath.sol";
import "./lib/Path.sol";

contract NFT is ERC721 {
    using Path for bytes;
    error NotAuthorized();
    error PositionNotCleared();

    event AddLiquidity(
        uint256 indexed tokenId,
        uint128 liquidity,
        uint256 amount0,
        uint256 amount1
    );

    uint256 public totalSupply;
    uint256 private nextTokenId;

    address public immutable factory;

    mapping(uint256 => HelpFunctions.TokenPosition) public positions;
    mapping(address => uint256[]) public userOwnedPositions;
    mapping(uint256 => bool) public burnedIds;

    function tokenIDtoPosition(
        uint256 tokenID
    ) public view returns (address, int24, int24) {
        return (
            positions[tokenID].pool,
            positions[tokenID].lowerTick,
            positions[tokenID].upperTick
        );
    }

    constructor(address factoryAddress) ERC721("NFT Positions", "PosNFT") {
        factory = factoryAddress;
    }

    error WrongToken();

    function tokenURI(
        uint256 tokenId
    ) public view override returns (string memory) {
        HelpFunctions.TokenPosition memory tokenPosition = positions[tokenId];

        if (tokenPosition.pool == address(0x00)) revert WrongToken();

        IUniswapV3Pool pool = IUniswapV3Pool(tokenPosition.pool);

        return
            NFTRenderer.render(
                NFTRenderer.RenderParams({
                    pool: tokenPosition.pool,
                    owner: address(this),
                    lowerTick: tokenPosition.lowerTick,
                    upperTick: tokenPosition.upperTick,
                    fee: pool.fee()
                })
            );
    }

    function mint(
        HelpFunctions.MintParams calldata params
    ) public returns (uint256 tokenId) {
        IUniswapV3Pool pool = HelpFunctions._getPool(
            factory,
            params.tokenA,
            params.tokenB,
            params.fee
        );

        (uint128 liquidity, uint256 amount0, uint256 amount1) = HelpFunctions
            ._addLiquidity(
                HelpFunctions.AddLiquidityInternalParams({
                    pool: pool,
                    lowerTick: params.lowerTick,
                    upperTick: params.upperTick,
                    amount0Desired: params.amount0Desired,
                    amount1Desired: params.amount1Desired,
                    amount0Min: params.amount0Min,
                    amount1Min: params.amount1Min
                })
            );

        tokenId = nextTokenId++;
        console.log(tokenId);
        _mint(params.recipient, tokenId);
        totalSupply++;

        HelpFunctions.TokenPosition memory tokenPosition = HelpFunctions
            .TokenPosition({
                pool: address(pool),
                lowerTick: params.lowerTick,
                upperTick: params.upperTick
            });

        positions[tokenId] = tokenPosition;
        userOwnedPositions[msg.sender].push(tokenId);

        emit AddLiquidity(tokenId, liquidity, amount0, amount1);
    }

    function burn(uint256 tokenId) public {
        address owner = ownerOf(tokenId);
        if (
            msg.sender != owner &&
            !(isApprovedForAll(owner, msg.sender)) &&
            getApproved(tokenId) != msg.sender
        ) revert NotAuthorized();

        HelpFunctions.TokenPosition memory tokenPosition = positions[tokenId];
        if (tokenPosition.pool == address(0x00)) revert WrongToken();

        IUniswapV3Pool pool = IUniswapV3Pool(tokenPosition.pool);
        (uint128 liquidity, , , uint128 tokensOwed0, uint128 tokensOwed1) = pool
            .positions(HelpFunctions._poolPositionKey(tokenPosition));

        if (liquidity > 0 || tokensOwed0 > 0 || tokensOwed1 > 0)
            revert PositionNotCleared();

        delete positions[tokenId];
        burnedIds[tokenId] = true;
        _burn(tokenId);
        totalSupply--;
    }

    function uniswapV3MintCallback(
        uint256 amount0,
        uint256 amount1,
        bytes calldata data
    ) public {
        IUniswapV3Pool.CallbackData memory extra = abi.decode(
            data,
            (IUniswapV3Pool.CallbackData)
        );
        IERC20(extra.token0).transferFrom(extra.payer, msg.sender, amount0);
        IERC20(extra.token1).transferFrom(extra.payer, msg.sender, amount1);
    }

    /// @notice Returns a list of all Liquidity Token IDs assigned to an address.
    /// @param _owner The owner whose Kitties we are interested in.
    /// @dev This method MUST NEVER be called by smart contract code. First, it's fairly
    ///  expensive (it walks the entire token array looking for tokens belonging to owner),
    ///  but it also returns a dynamic array, which is only supported for web3 calls, and
    ///  not contract-to-contract calls.
    function tokensOfOwner(
        address _owner
    ) external view returns (uint256[] memory ownerTokens) {
        uint256 tokenCount = balanceOf(_owner);

        if (tokenCount == 0) {
            // Return an empty array
            return new uint256[](0);
        } else {
            uint256[] memory result = new uint256[](tokenCount);
            uint256 totalTokens = totalSupply;
            uint256 resultIndex = 0;

            // We count on the fact that all tokens have IDs starting at 0 and increasing
            // sequentially up to the totalSupply count.
            uint256 tokenId;

            while (resultIndex < totalTokens) {
                if (burnedIds[tokenId] != true) {
                    if (ownerOf(tokenId) == _owner) {
                        result[resultIndex] = tokenId;
                        resultIndex++;
                    }
                }
                tokenId++;
            }

            return result;
        }
    }
}
