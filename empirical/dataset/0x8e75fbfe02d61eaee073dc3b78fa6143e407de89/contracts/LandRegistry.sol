// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

// ═══════════════════════════════════════════════════════════════════════════
//  LAND REGISTRY — Registro Auditável de Lastro do GreenBlock Token (GBT)
//
//  Kairos Digital Asset Ltda. · CNPJ 59.593.006/0001-62
//
//  Registra on-chain cada área ambiental que lastreia o GBT, com:
//   - Metadados da área (nome, localização, hectares, m², bioma, matrícula)
//   - Hash IPFS do dossiê completo de documentação
//   - Merkle root para verificação de integridade de cada documento
//   - Status (ATIVA / SUSPENSA / APOSENTADA)
//   - Histórico de auditoria ambiental recorrente
//   - Contagem de tokens mintados/queimados por área
//
//  v2 — pós-auditoria interna. Mudanças:
//   - mint/burn são registrados pelo GBTToken acoplado (TOKEN_ROLE)
//   - Merkle via OZ MerkleProof, paginação, pause, anti-duplicação de matrícula
//   - RETIRED é terminal (não volta a ACTIVE)
//
//  Governança: operações de escrita exigem o multisig 2-de-3.
// ═══════════════════════════════════════════════════════════════════════════

import {AccessControlUpgradeable} from "@openzeppelin/contracts-upgradeable/access/AccessControlUpgradeable.sol";
import {PausableUpgradeable} from "@openzeppelin/contracts-upgradeable/utils/PausableUpgradeable.sol";
import {UUPSUpgradeable} from "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import {Initializable} from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import {MerkleProof} from "@openzeppelin/contracts/utils/cryptography/MerkleProof.sol";

/**
 * @title LandRegistry
 * @notice Registro on-chain das áreas ambientais que lastreiam o GBT.
 * @dev Upgradeable UUPS. Governança via AccessControl + Safe multisig 2-de-3.
 * @custom:security-contact security@kairosdigitalasset.com.br
 */
contract LandRegistry is
    Initializable,
    AccessControlUpgradeable,
    PausableUpgradeable,
    UUPSUpgradeable
{
    // ───────────────────────────── ROLES ─────────────────────────────

    /// @notice Role que registra e atualiza áreas (vinculado ao multisig)
    bytes32 public constant REGISTRAR_ROLE = keccak256("REGISTRAR_ROLE");

    /// @notice Role concedido ao contrato GBTToken acoplado, que registra
    ///         automaticamente os mints/burns (mantém o lastro sincronizado on-chain).
    bytes32 public constant TOKEN_ROLE = keccak256("TOKEN_ROLE");

    /// @notice Role que autoriza upgrades do contrato
    bytes32 public constant UPGRADER_ROLE = keccak256("UPGRADER_ROLE");

    // ─────────────────────────── ENUMS / STRUCTS ─────────────────────

    /// @notice Status operacional de uma área
    enum LandStatus {
        ACTIVE,    // 0 — ativa e lastreando tokens
        SUSPENDED, // 1 — suspensa temporariamente (ex: pendência documental)
        RETIRED    // 2 — removida do projeto (tokens correspondentes queimados)
    }

    /// @notice Estrutura completa de uma área ambiental
    struct Land {
        uint256 id;                 // identificador sequencial (= índice; mantido p/ retorno em views)
        string name;                // "Fazenda Campo Verde I"
        string location;            // "Buritirama/BA"
        uint256 hectares;           // área em hectares
        uint256 squareMeters;       // área em m² (= GBT lastreável)
        string biome;               // "Caatinga" | "Cerrado" | "Amazônia"
        string matricula;           // matrícula no cartório
        string cartorio;            // nome do cartório
        string ipfsDocumentsHash;   // hash IPFS do dossiê completo
        bytes32 documentsRootHash;  // Merkle root dos documentos (integridade)
        uint256 tokensMinted;       // GBT já mintados com lastro nesta área
        uint256 tokensBurned;       // GBT já queimados desta área
        uint256 lastAuditTimestamp; // data do último laudo de auditoria ambiental
        string lastAuditIPFS;       // hash IPFS do último laudo
        LandStatus status;          // status atual
        uint256 registeredAt;       // timestamp do registro inicial
    }

    /// @notice Parâmetros de entrada para registro de área (evita stack too deep)
    struct LandInput {
        string name;
        string location;
        uint256 hectares;
        uint256 squareMeters;
        string biome;
        string matricula;
        string cartorio;
        string ipfsDocumentsHash;
        bytes32 documentsRootHash;
    }

    // ──────────────────────────── STORAGE ────────────────────────────

    /// @notice Lista de todas as áreas registradas
    Land[] private _lands;

    /// @notice Soma de m² de todas as áreas ativas
    uint256 public totalActiveSquareMeters;

    /// @notice Impede registro de matrícula duplicada (keccak da matrícula => existe)
    mapping(bytes32 => bool) public matriculaRegistered;

    /// @notice Endereço atual do GBTToken acoplado (com TOKEN_ROLE).
    /// @dev Mantém referência única; setTokenContract revoga o anterior.
    address public tokenContract;

    /// @dev Storage gap para futuras variáveis em upgrades.
    uint256[44] private __gap;

    // ──────────────────────────── EVENTS ─────────────────────────────

    event LandRegistered(
        uint256 indexed landId,
        string name,
        string location,
        uint256 squareMeters,
        string biome,
        string ipfsDocumentsHash,
        bytes32 documentsRootHash,
        uint256 timestamp
    );

    event LandDocumentsUpdated(
        uint256 indexed landId,
        string newIpfsHash,
        bytes32 newRootHash,
        uint256 timestamp
    );

    event LandAuditUpdated(
        uint256 indexed landId,
        string auditIPFS,
        uint256 timestamp
    );

    event LandStatusChanged(
        uint256 indexed landId,
        LandStatus oldStatus,
        LandStatus newStatus,
        string reason,
        uint256 timestamp
    );

    event TokensMintedRecorded(uint256 indexed landId, uint256 amount, uint256 newTotal);
    event TokensBurnedRecorded(uint256 indexed landId, uint256 amount, uint256 newTotal);
    event TokenContractSet(address indexed oldToken, address indexed newToken);

    // ──────────────────────────── ERRORS ─────────────────────────────

    error InvalidLandId(uint256 landId);
    error EmptyString();
    error ZeroAddress();
    error ZeroSquareMeters();
    error ZeroRootHash();
    error ZeroAmount();
    error LandNotActive(uint256 landId);
    error MintExceedsLandSize(uint256 landId, uint256 attempted, uint256 capacity);
    error BurnExceedsMinted(uint256 landId, uint256 attempted, uint256 available);
    error SameStatus();
    error CannotRevertRetirement(uint256 landId);
    error MatriculaAlreadyRegistered(string matricula);

    // ─────────────────────────── INITIALIZER ─────────────────────────

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    /**
     * @notice Inicializa o registro.
     * @param multisig Safe multisig 2-de-3 que recebe os roles administrativos.
     * @param upgrader Endereço que autoriza upgrades (Timelock 48h na mainnet).
     */
    function initialize(address multisig, address upgrader) public initializer {
        if (multisig == address(0) || upgrader == address(0)) revert ZeroAddress();

        __AccessControl_init();
        __Pausable_init();
        __UUPSUpgradeable_init();

        _grantRole(DEFAULT_ADMIN_ROLE, multisig);
        _grantRole(REGISTRAR_ROLE, multisig);
        _grantRole(UPGRADER_ROLE, upgrader);
    }

    /**
     * @notice Conecta o contrato GBTToken, concedendo a ele o TOKEN_ROLE.
     * @dev Acoplamento 1:1 — se já houver um token configurado, REVOGA o TOKEN_ROLE
     *      anterior antes de conceder ao novo. Garante que só um endereço tem o role.
     *      Apenas admin (multisig).
     */
    function setTokenContract(address token) external onlyRole(DEFAULT_ADMIN_ROLE) {
        if (token == address(0)) revert ZeroAddress();
        address old = tokenContract;
        if (old != address(0)) {
            _revokeRole(TOKEN_ROLE, old);
        }
        tokenContract = token;
        _grantRole(TOKEN_ROLE, token);
        emit TokenContractSet(old, token);
    }

    // ──────────────────────── REGISTRO DE ÁREA ───────────────────────

    /**
     * @notice Registra uma nova área ambiental (operação separada do mint).
     * @dev Apenas multisig (REGISTRAR_ROLE). A área entra como ACTIVE com 0 tokens.
     * @return landId Identificador sequencial da área registrada.
     */
    function registerLand(LandInput calldata input)
        external
        onlyRole(REGISTRAR_ROLE)
        whenNotPaused
        returns (uint256 landId)
    {
        if (bytes(input.name).length == 0) revert EmptyString();
        if (bytes(input.ipfsDocumentsHash).length == 0) revert EmptyString();
        if (bytes(input.matricula).length == 0) revert EmptyString();
        if (input.squareMeters == 0) revert ZeroSquareMeters();
        if (input.documentsRootHash == bytes32(0)) revert ZeroRootHash();

        // Impede registrar a mesma matrícula duas vezes
        bytes32 matriculaKey = keccak256(bytes(input.matricula));
        if (matriculaRegistered[matriculaKey]) {
            revert MatriculaAlreadyRegistered(input.matricula);
        }
        matriculaRegistered[matriculaKey] = true;

        landId = _lands.length;

        _lands.push(
            Land({
                id: landId,
                name: input.name,
                location: input.location,
                hectares: input.hectares,
                squareMeters: input.squareMeters,
                biome: input.biome,
                matricula: input.matricula,
                cartorio: input.cartorio,
                ipfsDocumentsHash: input.ipfsDocumentsHash,
                documentsRootHash: input.documentsRootHash,
                tokensMinted: 0,
                tokensBurned: 0,
                lastAuditTimestamp: 0,
                lastAuditIPFS: "",
                status: LandStatus.ACTIVE,
                registeredAt: block.timestamp
            })
        );

        totalActiveSquareMeters += input.squareMeters;

        emit LandRegistered(
            landId,
            input.name,
            input.location,
            input.squareMeters,
            input.biome,
            input.ipfsDocumentsHash,
            input.documentsRootHash,
            block.timestamp
        );
    }

    // ─────────────────── ATUALIZAÇÃO DE DOCUMENTOS ───────────────────

    /**
     * @notice Atualiza o dossiê de documentação de uma área (novo IPFS + Merkle).
     * @dev Usado quando documentos são atualizados/complementados. Apenas multisig.
     */
    function updateLandDocuments(
        uint256 landId,
        string calldata newIpfsHash,
        bytes32 newRootHash
    ) external onlyRole(REGISTRAR_ROLE) {
        _requireValidLand(landId);
        if (bytes(newIpfsHash).length == 0) revert EmptyString();
        if (newRootHash == bytes32(0)) revert ZeroRootHash();

        _lands[landId].ipfsDocumentsHash = newIpfsHash;
        _lands[landId].documentsRootHash = newRootHash;

        emit LandDocumentsUpdated(landId, newIpfsHash, newRootHash, block.timestamp);
    }

    /**
     * @notice Registra um novo laudo de auditoria ambiental recorrente.
     * @dev A auditoria ambiental é responsabilidade da BBC (Cláusula 2.1.e). Apenas multisig.
     */
    function updateAudit(uint256 landId, string calldata auditIPFS)
        external
        onlyRole(REGISTRAR_ROLE)
    {
        _requireValidLand(landId);
        if (bytes(auditIPFS).length == 0) revert EmptyString();

        _lands[landId].lastAuditTimestamp = block.timestamp;
        _lands[landId].lastAuditIPFS = auditIPFS;

        emit LandAuditUpdated(landId, auditIPFS, block.timestamp);
    }

    // ───────────────────────── STATUS DA ÁREA ────────────────────────

    /**
     * @notice Suspende uma área temporariamente (ex: pendência documental).
     * @dev Apenas multisig. Remove os m² do total ativo.
     */
    function suspendLand(uint256 landId, string calldata reason)
        external
        onlyRole(REGISTRAR_ROLE)
    {
        _requireValidLand(landId);
        _changeStatus(landId, LandStatus.SUSPENDED, reason);
    }

    /**
     * @notice Reativa uma área suspensa.
     * @dev Apenas multisig. Recoloca os m² no total ativo.
     */
    function reactivateLand(uint256 landId, string calldata reason)
        external
        onlyRole(REGISTRAR_ROLE)
    {
        _requireValidLand(landId);
        _changeStatus(landId, LandStatus.ACTIVE, reason);
    }

    /**
     * @notice Aposenta uma área (removida definitivamente do projeto).
     * @dev Apenas multisig. Os tokens correspondentes devem ser queimados via GBTToken.burnBatch.
     */
    function retireLand(uint256 landId, string calldata reason)
        external
        onlyRole(REGISTRAR_ROLE)
    {
        _requireValidLand(landId);
        _changeStatus(landId, LandStatus.RETIRED, reason);
    }

    // ──────────────────── CONTAGEM DE TOKENS POR ÁREA ────────────────

    /**
     * @notice Registra a contagem de tokens mintados para uma área.
     * @dev Chamado AUTOMATICAMENTE pelo GBTToken acoplado (TOKEN_ROLE) durante o mint.
     *      Valida que não excede a capacidade da área (m²). Garante lastro on-chain.
     */
    function recordTokensMinted(uint256 landId, uint256 amount)
        external
        onlyRole(TOKEN_ROLE)
    {
        _requireValidLand(landId);
        if (amount == 0) revert ZeroAmount();
        if (_lands[landId].status != LandStatus.ACTIVE) revert LandNotActive(landId);

        Land storage land = _lands[landId];
        uint256 capacityWei = land.squareMeters * 1e18;
        uint256 newMinted = land.tokensMinted + amount;
        if (newMinted > capacityWei) {
            revert MintExceedsLandSize(landId, newMinted, capacityWei);
        }

        land.tokensMinted = newMinted;
        emit TokensMintedRecorded(landId, amount, newMinted);
    }

    /**
     * @notice Registra a contagem de tokens queimados de uma área.
     * @dev Chamado AUTOMATICAMENTE pelo GBTToken acoplado (TOKEN_ROLE) durante o burn.
     */
    function recordTokensBurned(uint256 landId, uint256 amount)
        external
        onlyRole(TOKEN_ROLE)
    {
        _requireValidLand(landId);
        if (amount == 0) revert ZeroAmount();

        Land storage land = _lands[landId];
        uint256 available = land.tokensMinted - land.tokensBurned;
        if (amount > available) {
            revert BurnExceedsMinted(landId, amount, available);
        }

        land.tokensBurned += amount;
        emit TokensBurnedRecorded(landId, amount, land.tokensBurned);
    }

    // ──────────────────── GETTERS PARA O TOKEN (interface) ───────────

    /// @notice Capacidade em m² de uma área (= teto de GBT). Usado pelo token no mint.
    function landSquareMeters(uint256 landId) external view returns (uint256) {
        _requireValidLand(landId);
        return _lands[landId].squareMeters;
    }

    /// @notice Status de uma área. Usado pelo token no mint.
    function landStatus(uint256 landId) external view returns (LandStatus) {
        _requireValidLand(landId);
        return _lands[landId].status;
    }

    /// @notice Tokens já mintados para uma área. Usado pelo token.
    function landTokensMinted(uint256 landId) external view returns (uint256) {
        _requireValidLand(landId);
        return _lands[landId].tokensMinted;
    }

    // ──────────────────────────── VIEWS ──────────────────────────────

    /// @notice Retorna os dados completos de uma área.
    function getLand(uint256 landId) external view returns (Land memory) {
        _requireValidLand(landId);
        return _lands[landId];
    }

    /// @notice Retorna todas as áreas registradas.
    /// @dev Use com cautela: pode ficar custoso com muitas áreas. Prefira getLands paginado.
    function getAllLands() external view returns (Land[] memory) {
        return _lands;
    }

    /// @notice Retorna áreas de forma paginada (evita custo/limite com muitas áreas).
    /// @param offset Índice inicial.
    /// @param limit Quantidade máxima a retornar.
    function getLands(uint256 offset, uint256 limit)
        external
        view
        returns (Land[] memory)
    {
        uint256 total = _lands.length;
        if (offset >= total) return new Land[](0);
        uint256 end = offset + limit > total ? total : offset + limit;
        uint256 size = end - offset;
        Land[] memory result = new Land[](size);
        for (uint256 i = 0; i < size; i++) {
            result[i] = _lands[offset + i];
        }
        return result;
    }

    /// @notice Número total de áreas registradas.
    function totalLands() external view returns (uint256) {
        return _lands.length;
    }

    /// @notice Tokens líquidos (mintados - queimados) lastreados em uma área.
    function netTokensByLand(uint256 landId) external view returns (uint256) {
        _requireValidLand(landId);
        return _lands[landId].tokensMinted - _lands[landId].tokensBurned;
    }

    /**
     * @notice Verifica se um documento pertence ao Merkle tree registrado de uma área.
     * @dev Usa a biblioteca auditada MerkleProof da OpenZeppelin.
     * @param landId Área a verificar.
     * @param leaf Hash da folha (keccak256 do documento).
     * @param proof Prova de Merkle.
     */
    function verifyDocument(
        uint256 landId,
        bytes32 leaf,
        bytes32[] calldata proof
    ) external view returns (bool) {
        _requireValidLand(landId);
        return MerkleProof.verifyCalldata(proof, _lands[landId].documentsRootHash, leaf);
    }

    // ──────────────────────── INTERNAL HELPERS ───────────────────────

    function _requireValidLand(uint256 landId) private view {
        if (landId >= _lands.length) revert InvalidLandId(landId);
    }

    function _changeStatus(
        uint256 landId,
        LandStatus newStatus,
        string calldata reason
    ) private {
        Land storage land = _lands[landId];
        LandStatus oldStatus = land.status;
        if (oldStatus == newStatus) revert SameStatus();

        // RETIRED é terminal: área removida do projeto não volta.
        if (oldStatus == LandStatus.RETIRED) revert CannotRevertRetirement(landId);

        // Ajusta o total de m² ativos conforme a transição de status.
        bool wasActive = (oldStatus == LandStatus.ACTIVE);
        bool willBeActive = (newStatus == LandStatus.ACTIVE);

        if (wasActive && !willBeActive) {
            totalActiveSquareMeters -= land.squareMeters;
        } else if (!wasActive && willBeActive) {
            totalActiveSquareMeters += land.squareMeters;
        }

        land.status = newStatus;
        emit LandStatusChanged(landId, oldStatus, newStatus, reason, block.timestamp);
    }

    // ──────────────────────────── PAUSE ──────────────────────────────

    /// @notice Pausa registros/atualizações em emergência. Apenas admin (multisig).
    function pause() external onlyRole(DEFAULT_ADMIN_ROLE) {
        _pause();
    }

    /// @notice Retoma operações. Apenas admin (multisig).
    function unpause() external onlyRole(DEFAULT_ADMIN_ROLE) {
        _unpause();
    }

    /// @dev Autoriza upgrades. UPGRADER_ROLE (Timelock 48h na mainnet).
    function _authorizeUpgrade(address newImplementation)
        internal
        override
        onlyRole(UPGRADER_ROLE)
    {}
}
