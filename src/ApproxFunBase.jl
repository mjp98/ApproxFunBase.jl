module ApproxFunBase
    using Base: AnyDict
using Base, BlockArrays, BandedMatrices, BlockBandedMatrices, DomainSets, IntervalSets,
            SpecialFunctions, AbstractFFTs, FFTW, SpecialFunctions, DSP, DualNumbers,
            LinearAlgebra, SparseArrays, LowRankApprox, FillArrays, InfiniteArrays, InfiniteLinearAlgebra #, Arpack
import StaticArrays, Calculus

import DomainSets: Domain, indomain, UnionDomain, ProductDomain, FullSpace, Point, elements, DifferenceDomain,
            Interval, ChebyshevInterval, boundary, ∂, rightendpoint, leftendpoint,
            dimension, WrappedDomain, VcatDomain, component, components, ncomponents



import AbstractFFTs: Plan, fft, ifft
import FFTW: plan_r2r!, fftwNumber, REDFT10, REDFT01, REDFT00, RODFT00, R2HC, HC2R,
                r2r!, r2r,  plan_fft, plan_ifft, plan_ifft!, plan_fft!


import Base: values, convert, getindex, setindex!, *, +, -, ==, <, <=, >, |, !, !=, eltype, iterate,
                >=, /, ^, \, ∪, transpose, size, tail, broadcast, broadcast!, copyto!, copy, to_index, (:),
                similar, map, vcat, hcat, hvcat, show, summary, stride, sum, cumsum, sign, imag, conj, inv,
                complex, reverse, exp, sqrt, abs, abs2, sign, issubset, values, in, first, last, rand, intersect, setdiff,
                isless, union, angle, join, isnan, isapprox, isempty, sort, merge, promote_rule,
                minimum, maximum, extrema, argmax, argmin, findmax, findmin, isfinite,
                zeros, zero, one, promote_rule, repeat, length, resize!, isinf,
                getproperty, findfirst, unsafe_getindex, fld, cld, div, imag,
                @_inline_meta, eachindex, firstindex, lastindex, keys, isreal, OneTo,
                Array, Vector, Matrix, view, ones, @propagate_inbounds, print_array,
                split, iszero, permutedims

import Base.Broadcast: BroadcastStyle, Broadcasted, AbstractArrayStyle, broadcastable,
                        DefaultArrayStyle, broadcasted

import Statistics: mean

import LinearAlgebra: BlasInt, BlasFloat, norm, ldiv!, mul!, det, eigvals, cross,
                        qr, qr!, rank, isdiag, istril, istriu, issymmetric, ishermitian,
                        Tridiagonal, diagm, diagm_container, factorize, nullspace,
                        Hermitian, Symmetric, adjoint, transpose, char_uplo

import SparseArrays: blockdiag

# import Arpack: eigs

# we need to import all special functions to use Calculus.symbolic_derivatives_1arg
# we can't do importall Base as we replace some Base definitions
import SpecialFunctions: sinpi, cospi, airy, besselh,
                    asinh, acosh,atanh, erfcx, dawson, erf, erfi,
                    sin, cos, sinh, cosh, airyai, airybi, airyaiprime, airybiprime,
                    hankelh1, hankelh2, besselj, besselj0, bessely, besseli, besselk,
                    besselkx, hankelh1x, hankelh2x, exp2, exp10, log2, log10,
                    tan, tanh, csc, asin, acsc, sec, acos, asec,
                    cot, atan, acot, sinh, csch, asinh, acsch,
                    sech, acosh, asech, tanh, coth, atanh, acoth,
                    expm1, log1p, lfact, sinc, cosc, erfinv, erfcinv, beta, lbeta,
                    eta, zeta, gamma,  lgamma, polygamma, invdigamma, digamma, trigamma,
                    abs, sign, log, expm1, tan, abs2, sqrt, angle, max, min, cbrt, log,
                    atan, acos, asin, erfc, inv

import StaticArrays: SVector

import BandedMatrices: bandrange, bandshift,
                        inbands_getindex, inbands_setindex!, bandwidth, AbstractBandedMatrix,
                        colstart, colstop, colrange, rowstart, rowstop, rowrange,
                        bandwidths, _BandedMatrix, BandedMatrix

import BlockArrays: blocksize, block, blockaxes, blockindex
import BlockBandedMatrices: blockbandwidth, blockbandwidths, blockcolstop, blockcolrange,
                            blockcolstart, blockrowstop, blockrowstart, blockrowrange,
                            subblockbandwidth, subblockbandwidths, _BlockBandedMatrix,
                            _BandedBlockBandedMatrix, BandedBlockBandedMatrix, BlockBandedMatrix,
                            isblockbanded, isbandedblockbanded, bb_numentries, BlockBandedSizes

import FillArrays: AbstractFill, getindex_value
import LazyArrays: cache, CachedVector, cacheddata
import InfiniteArrays: PosInfinity, InfRanges, AbstractInfUnitRange, OneToInf, InfiniteCardinal


# convenience for 1-d block ranges
const BlockRange1 = BlockRange{1,Tuple{UnitRange{Int}}}

import Base: view

import StaticArrays: StaticArray, SVector

import DomainSets: dimension

import IntervalSets: (..), endpoints

const Vec{d,T} = SVector{d,T}

export pad!, pad, chop!, sample,
       complexroots, roots, svfft, isvfft,
       reverseorientation, jumplocations

export .., Interval, ChebyshevInterval, leftendpoint, rightendpoint, endpoints, cache


if VERSION < v"1.6-"
	oneto(n) = Base.OneTo(n)
else
	import Base: oneto
end


include("LinearAlgebra/LinearAlgebra.jl")
include("Fun.jl")
include("Domains/Domains.jl")
include("Multivariate/Multivariate.jl")
include("Operators/Operator.jl")
include("Caching/caching.jl")
include("PDE/PDE.jl")
include("Spaces/Spaces.jl")
include("hacks.jl")
include("testing.jl")
include("specialfunctions.jl")
include("show.jl")

end #module
