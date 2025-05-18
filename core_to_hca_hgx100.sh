#!/bin/bash
# core_to_hca_hgx.sh - Custom mapping script for ConnectX-7 HCAs to core affinity
#
# This script maps CX7 HCAs to cores based on NUMA locality for optimal performance
# System configuration for CX7 adapters:
# - 4x ConnectX7 (mlx5_0 to mlx5_3) on NUMA 0
# - 4x ConnectX7 (mlx5_8 to mlx5_11) on NUMA 2
#
# NUMA layout:
# NUMA node0 CPU(s): 0-23,96-119
# NUMA node2 CPU(s): 48-71,144-167

# Function to log information if verbose mode is enabled
log_info() {
    if [[ -n "$VERBOSE" && "$VERBOSE" -eq 1 ]]; then
        echo "[INFO] $1" >&2
    fi
}

# Get local rank from MPI environment variable
local_rank=${OMPI_COMM_WORLD_LOCAL_RANK:-0}
log_info "Local rank: $local_rank"

# Map local rank to core and CX7 HCA with NUMA locality in mind
case $local_rank in
    # ConnectX7 adapters on NUMA 0
    0) core=0,96;      export UCX_NET_DEVICES=mlx5_0:1; hca="mlx5_0" ;;
    1) core=1,97;      export UCX_NET_DEVICES=mlx5_1:1; hca="mlx5_1" ;;
    2) core=2,98;      export UCX_NET_DEVICES=mlx5_2:1; hca="mlx5_2" ;;
    3) core=3,99;      export UCX_NET_DEVICES=mlx5_3:1; hca="mlx5_3" ;;

    # ConnectX7 adapters on NUMA 2
    4) core=48,144;    export UCX_NET_DEVICES=mlx5_8:1; hca="mlx5_8" ;;
    5) core=49,145;    export UCX_NET_DEVICES=mlx5_9:1; hca="mlx5_9" ;;
    6) core=50,146;    export UCX_NET_DEVICES=mlx5_10:1; hca="mlx5_10" ;;
    7) core=51,147;    export UCX_NET_DEVICES=mlx5_11:1; hca="mlx5_11" ;;

    # Additional mappings for higher rank processes (still using CX7 HCAs)
    # Using different cores on the same NUMA node
    8) core=4,100;     export UCX_NET_DEVICES=mlx5_0:1; hca="mlx5_0" ;;
    9) core=5,101;     export UCX_NET_DEVICES=mlx5_1:1; hca="mlx5_1" ;;
    10) core=6,102;    export UCX_NET_DEVICES=mlx5_2:1; hca="mlx5_2" ;;
    11) core=7,103;    export UCX_NET_DEVICES=mlx5_3:1; hca="mlx5_3" ;;
    12) core=52,148;   export UCX_NET_DEVICES=mlx5_8:1; hca="mlx5_8" ;;
    13) core=53,149;   export UCX_NET_DEVICES=mlx5_9:1; hca="mlx5_9" ;;
    14) core=54,150;   export UCX_NET_DEVICES=mlx5_10:1; hca="mlx5_10" ;;
    15) core=55,151;   export UCX_NET_DEVICES=mlx5_11:1; hca="mlx5_11" ;;

    # Default case for ranks beyond explicit mapping
    *)
        # Calculate which CX7 HCA to use and corresponding core
        cx7_index=$((local_rank % 8))
        numa_node=0

        # Determine NUMA node based on CX7 index
        if [[ $cx7_index -le 3 ]]; then
            numa_node=0
            # Calculate offset within NUMA node 0 cores
            core_offset=$(( 8 + ((local_rank - 16) / 8) * 4 ))
            if [[ $core_offset -gt 20 ]]; then
                core_offset=20  # Cap at core 20 to stay within NUMA 0
            fi
            core="${core_offset},$(($core_offset + 96))"

            # Assign HCA based on index
            case $cx7_index in
                0) export UCX_NET_DEVICES=mlx5_0:1; hca="mlx5_0" ;;
                1) export UCX_NET_DEVICES=mlx5_1:1; hca="mlx5_1" ;;
                2) export UCX_NET_DEVICES=mlx5_2:1; hca="mlx5_2" ;;
                3) export UCX_NET_DEVICES=mlx5_3:1; hca="mlx5_3" ;;
            esac
        else
            numa_node=2
            # Calculate offset within NUMA node 2 cores
            core_offset=$(( 56 + ((local_rank - 16) / 8) * 4 ))
            if [[ $core_offset -gt 68 ]]; then
                core_offset=68  # Cap at core 68 to stay within NUMA 2
            fi
            core="${core_offset},$(($core_offset + 96))"

            # Assign HCA based on index
            case $cx7_index in
                4) export UCX_NET_DEVICES=mlx5_8:1; hca="mlx5_8" ;;
                5) export UCX_NET_DEVICES=mlx5_9:1; hca="mlx5_9" ;;
                6) export UCX_NET_DEVICES=mlx5_10:1; hca="mlx5_10" ;;
                7) export UCX_NET_DEVICES=mlx5_11:1; hca="mlx5_11" ;;
            esac
        fi
        ;;
esac

# Export HCA name for debugging or logging purposes
export CLUSTERKIT_HCA_NAME=$hca

# Log the mapping if verbose mode is enabled
log_info "Mapping rank $local_rank to core(s) $core and CX7 HCA $hca (NUMA node $numa_node)"

# Execute the command with CPU affinity
exec taskset -c $core "$@"
