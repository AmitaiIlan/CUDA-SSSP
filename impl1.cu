#include <vector>
#include <iostream>

#include "cuda_error_check.cuh"
#include "utils.hpp"

__device__ int min_kernel(int a, int b){
	return a < b? a : b;
}

__global__ void impl1_kernel(edge* edges, int nEdges, int* distance, int* anyChange){
	const int idx = blockDim.x*blockIdx.x + threadIdx.x;
	const int nThreads = blockDim.x * gridDim.x;
	const int nWarps = nThreads%32 == 0? nThreads/32 : nThreads/32+1; //number of warps
	const int lane = idx & 31; //thread offset within a warp
	const int warpid = idx >> 5;

	int load = nEdges%nWarps == 0? nEdges/nWarps : nEdges/nWarps+1;
	int beg = load*warpid;
	int end = min_kernel(nEdges,beg+load);
	beg = beg+lane;

	for(int i = beg; i < end; i++){
		int u = edges[i].src;
		int v = edges[i].dest;
		int w = edges[i].w;
		int temp_dist = distance[u]+w;
		if(distance[u] == INF) continue;
		if(temp_dist < distance[v]){
			atomicMin(&distance[v], temp_dist);
			*anyChange = 1;
		}
	}
}

void impl1(int* results, edge* h_edges, int nEdges, int n, int blockSize, int blockNum){
	int nb = n*sizeof(int);
	int* d_anyChange = NULL;
	edge* d_edges = NULL;
	int* d_distance = NULL;
	cudaMalloc((void**)&d_edges,nEdges*sizeof(edge));
	cudaMalloc((void**)&d_distance,nb);
	cudaMalloc((void**)&d_anyChange,sizeof(int));
	cudaMemcpy(d_edges,h_edges,nEdges*sizeof(edge),cudaMemcpyHostToDevice);
	cudaMemcpy(d_distance,results,nb,cudaMemcpyHostToDevice);

	int nIter = 0;
    	setTime();
	for(int i = 0; i < n-1; i++){
		nIter++;
		cudaMemset(d_anyChange, 0,sizeof(int));
		impl1_kernel<<<blockNum,blockSize>>>(d_edges,nEdges,d_distance,d_anyChange);
	
		//break from loop if no changes
		int anyChange = 0;
		cudaMemcpy(&anyChange,d_anyChange, sizeof(int),cudaMemcpyDeviceToHost);
		if(!anyChange) break;
	}
	cout << "Time: " << getTime() << "ms\n";
	cout << "Iterations: " << nIter << "\n";
	
	cudaMemcpy(results,d_distance,nb,cudaMemcpyDeviceToHost);
	
	cudaFree(d_edges);
	cudaFree(d_distance);
	cudaFree(d_anyChange);
}