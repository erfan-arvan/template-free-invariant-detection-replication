#!/bin/bash -l
#SBATCH --job-name=io-examples-s5
#SBATCH --output=%x.%j.out
#SBATCH --error=%x.%j.err
#SBATCH --partition=general
#SBATCH --qos=standard
#SBATCH --account=mjk76
#SBATCH --nodes=1
#SBATCH --ntasks=1
#SBATCH --cpus-per-task=8
#SBATCH --mem=280G
#SBATCH --time=04:00:00

set -euo pipefail
cd /project/mjk76/ea442/promptstudy
source ./lib_io_examples_common.sh

IO_JAR="/project/mjk76/ea442/promptstudy/io-examples-tool.jar"
OUT_DIR="/scratch/mjk76/ea442/promptstudy"

run_io_examples "apollo-s5" "$OUT_DIR/apollo-s5-chicory/apollo-biz/src/main/java" "$OUT_DIR/apollo-s5-chicory-out/latest/dtrace.gz" "$OUT_DIR" "Java/17.0.15" "$IO_JAR"
run_io_examples "dubbo-s5"  "$OUT_DIR/dubbo-s5-chicory/dubbo-common/src/main/java" "$OUT_DIR/dubbo-s5-chicory-out/latest/dtrace.gz" "$OUT_DIR" "Java/17.0.15" "$IO_JAR"
run_io_examples "hudi-s5"   "$OUT_DIR/hudi-s5-chicory/hudi-client/hudi-java-client/src/main/java" "$OUT_DIR/hudi-s5-chicory-out/dtrace.gz" "$OUT_DIR" "Java/17.0.15" "$IO_JAR"
# netty-s5 excluded here: job still running, no dtrace.gz yet. Run separately once it finishes:
# run_io_examples "netty-s5"  "$OUT_DIR/netty-s5-chicory/common/src/main/java" "$OUT_DIR/netty-s5-chicory-out/latest/dtrace.gz" "$OUT_DIR" "Java/17.0.15" "$IO_JAR"
run_io_examples "spring-s5" "$OUT_DIR/spring-s5-chicory/spring-core/src/main/java" "$OUT_DIR/spring-s5-chicory-out/dtrace.gz" "$OUT_DIR" "Java/17.0.15" "$IO_JAR"
