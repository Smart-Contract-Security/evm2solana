Paper: Understanding the Porting Gap from EVM Smart Contracts to Solana via Solang: An Empirical Study

## Repository Structure
```
dataset/                  # RQ4 evaluation dataset (100 projects)
src/
    build_dataset/        # build dataset for RQ4 (100 projects)
    empirical/            # Dataset construction for all empirical (1,151) + RQ2 Solang compilation analysis
    scan_pattern/         # RQ1 incompatibility-pattern AST scanning
    scan_external/        # RQ3 external-protocol dependency scanning
    llm_study/            # RQ4 LLM porting
    evaluate_llm_study/   # RQ4 evaluation of ported projects
    synthesized_dataset/  # Synthetic dataset compilation scripts in RQ1
synthesized_dataset/      # RQ1 synthetic data (40 minimal contracts, one per pattern)
rewrite_synthesized/      # Manually rewritten synthetic contracts
dual_coding/              # RQ1 open-coding artifacts (researchers + agent)
logs/                     # Run logs and analysis results (backing the paper's numbers)
    build_dataset/        # RQ4 sampling intermediates
    empirical/            # Crawl, dedup, Solang compilation, pattern/protocol scan results
    evaluate_llm/         # RQ4 evaluation results (compile, diff, error count, interface diff)
    llm_study_pure_llm/            # RQ4 strategy 1
    llm_study_feedback/            # RQ4 strategy 2
    llm_study_knowledge_feedback/  # RQ4 strategy 3
    synthesized_dataset/  # Synthetic dataset compilation logs
results/                  # RQ4 ported projects from the three LLM strategies
    deepseek/
        llm_study_pure_llm/            # RQ4 Strategy 1 output
        llm_study_feedback/            # RQ4 Strategy 2 output
        llm_study_knowledge_feedback/  # RQ4 Strategy 3 output
RQ2-top50.xlsx            # RQ2 Top-50 error type classification
requirements.txt          # Python dependencies
```

## Environment Variables

Create a `.env` file in the repository root:

```bash
ETHERSCAN_API_KEY=your_key
DEEPSEEK_API_KEY=your_key
```

## Reproduction

### 1. Build the empirical dataset (requires ETHERSCAN_API_KEY)
python src/empirical/crawl_from_etherscan.py
python src/empirical/dedup_mainfest.py
python src/empirical/compile_solc.py
python src/empirical/detect_lib_or_interface.py
python src/empirical/dedup_structural.py

### 2. RQ1: Scan incompatibility patterns
python src/scan_pattern/main.py

### 3. RQ2: Compile with Solang and analyze errors
python src/empirical/compile_solang.py
python src/empirical/analyze_solang.py

### 4. RQ3: Scan external-protocol dependencies
python src/scan_external/scan_external_protocols.py

### 5. RQ4: Stratified sampling (depends on RQ2 error analysis)
python src/build_dataset/1_build_candidate_pool.py
python src/build_dataset/2_sample.py
python src/build_dataset/3_copy_dataset.py

### 6. RQ4: LLM-based porting
python src/llm_study/main.py

### 7. RQ4: Evaluate ported projects
python src/evaluate_llm_study/1_compile_solang.py
python src/evaluate_llm_study/2_diff_text.py
python src/evaluate_llm_study/2.5_analyze_diff.py
python src/evaluate_llm_study/3_error_count.py
python src/evaluate_llm_study/4_analyze_compile_failures.py
python src/evaluate_llm_study/5_interface_diff.py
