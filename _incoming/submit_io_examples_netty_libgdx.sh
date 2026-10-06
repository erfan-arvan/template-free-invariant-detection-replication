#!/bin/bash -l
#SBATCH --job-name=io-examples-netty-spring
#SBATCH --output=%x.%j.out
#SBATCH --error=%x.%j.err
#SBATCH --partition=general
#SBATCH --qos=standard
#SBATCH --account=mjk76
#SBATCH --nodes=1
#SBATCH --ntasks=1
#SBATCH --cpus-per-task=8
#SBATCH --mem=280G
#SBATCH --time=24:00:00

set -euo pipefail
cd /project/mjk76/ea442/promptstudy
source ./lib_io_examples_common.sh

IO_JAR="/project/mjk76/ea442/promptstudy/io-examples-tool.jar"
OUT_DIR="/scratch/mjk76/ea442/promptstudy"
PROJECT_DIR="/project/mjk76/ea442/promptstudy"

# netty already succeeded once (job io-examples-netty-libgdx.1236938, wrote
# netty-s5_io_examples.json to $OUT_DIR) but that output was never copied
# back to $PROJECT_DIR -- rerunning is cheap (6s last time) and simpler than
# trying to locate/verify the old scratch copy is still there.
run_io_examples "netty-s5"  "$OUT_DIR/netty-s5-chicory/common/src/main/java"                        "$OUT_DIR" "Java/17.0.15" "$IO_JAR"

# spring has never been run at all -- src path matches
# submit_spring_chicory_trace_s5.sh's WORK_DIR/MODULE and COMBINED naming
# ("${OUT_DIR}/spring-s5-chicory", "${OUT_DIR}/spring-s5.dtrace").
run_io_examples "spring-s5" "$OUT_DIR/spring-s5-chicory/spring-core/src/main/java"                   "$OUT_DIR" "Java/17.0.15" "$IO_JAR"

# Copy both results back to $PROJECT_DIR so `ls` there actually shows them
# (this is what silently didn't happen for netty last time).
cp "$OUT_DIR/netty-s5_io_examples.json"  "$PROJECT_DIR/"
cp "$OUT_DIR/spring-s5_io_examples.json" "$PROJECT_DIR/"

echo ">>> Copied netty-s5_io_examples.json and spring-s5_io_examples.json to $PROJECT_DIR"
ls -la "$PROJECT_DIR"/netty-s5_io_examples.json "$PROJECT_DIR"/spring-s5_io_examples.json
