
export TensorSpace, ⊗, ProductSpace, factor, factors, nfactors

#  SV is a tuple of d spaces
abstract type AbstractProductSpace{SV,DD,RR} <: Space{DD,RR} end


spacetype(::AbstractProductSpace{SV},k) where {SV} = SV.parameters[k]


##### Tensorizer
# This gives the map from coefficients to the
# tensor entry of a tensor product of d spaces
# findfirst is overriden to get efficient inverse
# blocklengths is a tuple of block lengths, e.g., Chebyshev()^2
# would be Tensorizer((1:∞,1:∞))
# ConstantSpace() ⊗ Chebyshev()
# would be Tensorizer((1:1,1:∞))
# and Chebyshev() ⊗ ArraySpace([Chebyshev(),Chebyshev()])
# would be Tensorizer((1:∞,2:2:∞))


struct Tensorizer{DMS<:Tuple}
    blocks::DMS
end

const TrivialTensorizer{d} = Tensorizer{NTuple{d,Ones{Int,1,Tuple{OneToInf{Int}}}}}

Base.eltype(a::Tensorizer) = NTuple{length(a.blocks),Int}
Base.eltype(::Tensorizer{NTuple{d,T}}) where {d,T} = NTuple{d,Int}
dimensions(a::Tensorizer) = map(sum,a.blocks)
Base.length(a::Tensorizer) = mapreduce(sum,*,a.blocks)

# (blockrow,blockcol), (subrow,subcol), (rowshift,colshift), (numblockrows,numblockcols), (itemssofar, length)
start(a::Tensorizer{Tuple{AA,BB}}) where {AA,BB} = (1,1), (1,1), (0,0), (a.blocks[1][1],a.blocks[2][1]), (0,length(a))

function next(a::Tensorizer{Tuple{AA,BB}}, ((K,J), (k,j), (rsh,csh), (n,m), (i,tot))) where {AA,BB}
    ret = k+rsh,j+csh
    if k==n && j==m  # end of block
        if J == 1 || K == length(a.blocks[1])   # end of new block
            B = K+J # next block
            J = min(B, length(a.blocks[2]))::Int  # don't go past new block
            K = B-J+1   # K+J-1 == B
        else
            K,J = K+1,J-1
        end
        k = j = 1
        if i+1 < tot # not done yet
            n,m = a.blocks[1][K], a.blocks[2][J]
            rsh,csh = sum(a.blocks[1][1:K-1]), sum(a.blocks[2][1:J-1])
        end
    elseif k==n
        k  = 1
        j += 1
    else
        k += 1
    end
    ret, ((K,J), (k,j), (rsh,csh), (n,m), (i+1,tot))
end


done(a::Tensorizer, ((K,J), (k,j), (rsh,csh), (n,m), (i,tot))) = i ≥ tot

iterate(a::Tensorizer) = next(a, start(a))
function iterate(a::Tensorizer, st)
    done(a,st) && return nothing
    next(a, st)
end


cache(a::Tensorizer) = CachedIterator(a)

function Base.findfirst(::TrivialTensorizer{2},kj::Tuple{Int,Int})
    k,j=kj
    if k > 0 && j > 0
        n=k+j-2
        (n*(n+1))÷2+k
    else
        0
    end
end

function Base.findfirst(sp::Tensorizer{Tuple{<:AbstractFill{S},<:AbstractFill{T}}},kj::Tuple{Int,Int}) where {S,T}
    k,j=kj

    if k > 0 && j > 0
        a,b = getindex_value(sp.blocks[1]),getindex_value(sp.blocks[2])
        kb1,kr = fldmod(k-1,a)
        jb1,jr = fldmod(j-1,b)
        nb=kb1+jb1
        a*b*(nb*(nb+1)÷2+kb1)+a*jr+kr+1
    else
        0
    end
end

# which block of the tensor
# equivalent to sum of indices -1

# block(it::Tensorizer,k) = Block(sum(it[k])-length(it.blocks)+1)
block(ci::CachedIterator{T,TrivialTensorizer{2}},k::Int) where {T} =
    Block(k == 0 ? 0 : sum(ci[k])-length(ci.iterator.blocks)+1)

block(::TrivialTensorizer{2},n::Int) =
    Block(floor(Integer,sqrt(2n) + 1/2))

block(sp::Tensorizer{<:Tuple{<:AbstractFill{S},<:AbstractFill{T}}},n::Int) where {S,T} =
    Block(floor(Integer,sqrt(2floor(Integer,(n-1)/(getindex_value(sp.blocks[1])*getindex_value(sp.blocks[2])))+1) + 1/2))
_cumsum(x) = cumsum(x)
_cumsum(x::Number) = x
block(sp::Tensorizer,k::Int) = Block(findfirst(x->x≥k, _cumsum(blocklengths(sp))))
block(sp::CachedIterator,k::Int) = block(sp.iterator,k)

blocklength(it,k) = blocklengths(it)[k]
blocklength(it,k::Block) = blocklength(it,k.n[1])
blocklength(it,k::BlockRange) = blocklength(it,Int.(k))

blocklengths(::TrivialTensorizer{2}) = 1:∞



blocklengths(it::Tensorizer) = tensorblocklengths(it.blocks...)
blocklengths(it::CachedIterator) = blocklengths(it.iterator)

function getindex(it::TrivialTensorizer{2},n::Integer)
    m=block(it,n)
    p=findfirst(it,(1,m))
    j=1+n-p
    j,m-j+1
end

# could be cleaned up using blocks
function getindex(it::Tensorizer{<:Tuple{<:AbstractFill{S},<:AbstractFill{T}}},n::Integer) where {S,T}
    a,b = getindex_value(it.blocks[1]),getindex_value(it.blocks[2])
    nb1,nr = fldmod(n-1,a*b) # nb1 = "nb" - 1, i.e. using zero-base
    m1=block(it,n).n[1]-1
    pb1=fld(findfirst(it,(1,b*m1+1))-1,a*b)
    jb1=nb1-pb1
    kr1,jr1 = fldmod(nr,a)
    b*jb1+jr1+1,a*(m1-jb1)+kr1+1
end


blockstart(it,K)::Int = K==1 ? 1 : sum(blocklengths(it)[1:K-1])+1
blockstop(it,::PosInfinity) = ℵ₀
_K_sum(bl::AbstractVector, K) = sum(bl[1:K])
_K_sum(bl::Integer, K) = bl
blockstop(it, K)::Int = _K_sum(blocklengths(it), K)

blockstart(it,K::Block) = blockstart(it,K.n[1])
blockstop(it,K::Block) = blockstop(it,K.n[1])


blockrange(it,K) = blockstart(it,K):blockstop(it,K)
blockrange(it,K::BlockRange) = blockstart(it,first(K)):blockstop(it,last(K))




# convert from block, subblock to tensor
subblock2tensor(rt::TrivialTensorizer{2},K,k) =
    (k,K.n[1]-k+1)

subblock2tensor(rt::CachedIterator{II,TrivialTensorizer{2}},K,k) where {II} =
    (k,K.n[1]-k+1)


subblock2tensor(rt::CachedIterator,K,k) = rt[blockstart(rt,K)+k-1]

# tensorblocklengths gives calculates the block sizes of each tensor product
#  Tensor product degrees are taken to be the sum of the degrees
#  a degree is which block you are in


tensorblocklengths(a) = a   # a single block is not modified
tensorblocklengths(a, b) = conv(a,b)
tensorblocklengths(a,b,c,d...) = tensorblocklengths(tensorblocklengths(a,b),c,d...)


# TensorSpace
# represents the tensor product of several subspaces
"""
    TensorSpace(a::Space,b::Space)

represents a tensor product of two 1D spaces `a` and `b`.
The coefficients are interlaced in lexigraphical order.

For example, consider
```julia
Fourier()*Chebyshev()  # returns TensorSpace(Fourier(),Chebyshev())
```
This represents functions on `[-π,π) x [-1,1]`, using the Fourier basis for the first argument
and Chebyshev basis for the second argument, that is, `φ_k(x)T_j(y)`, where
```
φ_0(x) = 1,
φ_1(x) = sin x,
φ_2(x) = cos x,
φ_3(x) = sin 2x,
φ_4(x) = cos 2x
…
```
By Choosing `(k,j)` appropriately, we obtain a single basis:
```
φ_0(x)T_0(y) (= 1),
φ_0(x)T_1(y) (= y),
φ_1(x)T_0(y) (= sin x),
φ_0(x)T_2(y), …
```
"""
struct TensorSpace{SV,D,R} <:AbstractProductSpace{SV,D,R}
    spaces::SV
end

tensorizer(sp::TensorSpace) = Tensorizer(map(blocklengths,sp.spaces))
blocklengths(S::TensorSpace) = tensorblocklengths(map(blocklengths,S.spaces)...)


# the evaluation is *, so the type will be the same as *
# However, this fails for some any types
tensor_eval_type(a,b) = Base.promote_op(*,a,b)
tensor_eval_type(::Type{Vector{Any}},::Type{Vector{Any}}) = Vector{Any}
tensor_eval_type(::Type{Vector{Any}},_) = Vector{Any}
tensor_eval_type(_,::Type{Vector{Any}}) = Vector{Any}


TensorSpace(sp::Tuple) =
    TensorSpace{typeof(sp),typeof(mapreduce(domain,×,sp)),
                mapreduce(rangetype,(a,b)->tensor_eval_type(a,b),sp)}(sp)


dimension(sp::TensorSpace) = mapreduce(dimension,*,sp.spaces)

for OP in (:spacescompatible,:(==))
    @eval $OP(A::TensorSpace{SV,D,R},B::TensorSpace{SV,D,R}) where {SV,D,R} =
        all(Bool[$OP(A.spaces[k],B.spaces[k]) for k=1:length(A.spaces)])
end

canonicalspace(T::TensorSpace) = TensorSpace(map(canonicalspace,T.spaces))


TensorSpace(A::SVector{N,<:Space}) where N = TensorSpace(tuple(A...))
TensorSpace(A...) = TensorSpace(tuple(A...))
TensorSpace(A::ProductDomain) = TensorSpace(tuple(map(Space,components(A))...))
⊗(A::TensorSpace,B::TensorSpace) = TensorSpace(A.spaces...,B.spaces...)
⊗(A::TensorSpace,B::Space) = TensorSpace(A.spaces...,B)
⊗(A::Space,B::TensorSpace) = TensorSpace(A,B.spaces...)
⊗(A::Space,B::Space) = TensorSpace(A,B)

domain(f::TensorSpace) = ×(domain.(f.spaces)...)
Space(sp::ProductDomain) = TensorSpace(sp)

setdomain(sp::TensorSpace, d::ProductDomain) = TensorSpace(setdomain.(factors(sp), factors(d)))

*(A::Space, B::Space) = A⊗B
^(A::Space, p::Integer) = p == 1 ? A : A*A^(p-1)


## TODO: generalize
components(sp::TensorSpace{Tuple{S1,S2}}) where {S1<:Space{D,R},S2} where {D,R<:AbstractArray} =
    [s ⊗ sp.spaces[2] for s in components(sp.spaces[1])]

components(sp::TensorSpace{Tuple{S1,S2}}) where {S1,S2<:Space{D,R}} where {D,R<:AbstractArray} =
    [sp.spaces[1] ⊗ s for s in components(sp.spaces[2])]

Base.size(sp::TensorSpace{Tuple{S1,S2}}) where {S1<:Space{D,R},S2} where {D,R<:AbstractArray} =
    size(sp.spaces[1])

Base.size(sp::TensorSpace{Tuple{S1,S2}}) where {S1,S2<:Space{D,R}} where {D,R<:AbstractArray} =
    size(sp.spaces[2])

# TODO: Generalize to higher dimensions
getindex(sp::TensorSpace{Tuple{S1,S2}},k::Integer) where {S1<:Space{D,R},S2} where {D,R<:AbstractArray} =
    sp.spaces[1][k] ⊗ sp.spaces[2]

getindex(sp::TensorSpace{Tuple{S1,S2}},k::Integer) where {S1,S2<:Space{D,R}} where {D,R<:AbstractArray} =
    sp.spaces[1] ⊗ sp.spaces[2][k]


length(sp::TensorSpace{Tuple{S1,S2}}) where {S1<:Space{D,R},S2} where {D,R<:AbstractArray} =
    length(sp.spaces[1])

length(sp::TensorSpace{Tuple{S1,S2}}) where {S1,S2<:Space{D,R}} where {D,R<:AbstractArray} =
    length(sp.spaces[2])


iterate(sp::TensorSpace{Tuple{S1,S2}},k...) where {S1<:Space{D,R},S2} where {D,R<:AbstractArray} =
    iterate(components(sp),k...)

iterate(sp::TensorSpace{Tuple{S1,S2}},k...) where {S1,S2<:Space{D,R}} where {D,R<:AbstractArray} =
    iterate(components(sp),k...)


# every column is in the same space for a TensorSpace
# TODO: remove
columnspace(S::TensorSpace,_) = S.spaces[1]


struct ProductSpace{S<:Space,V<:Space,D,R} <: AbstractProductSpace{Tuple{S,V},D,R}
    spacesx::Vector{S}
    spacey::V
end

ProductSpace(spacesx::Vector,spacey) =
    ProductSpace{eltype(spacesx),typeof(spacey),typeof(mapreduce(domain,×,sp)),
                mapreduce(s->eltype(domain(s)),promote_type,sp)}(spacesx,spacey)

# TODO: This is a weird definition
⊗(A::Vector{S},B::Space) where {S<:Space} = ProductSpace(A,B)
domain(f::ProductSpace) = domain(f.spacesx[1])×domain(f.spacesy)


nfactors(d::AbstractProductSpace) = length(d.spaces)
factors(d::AbstractProductSpace) = d.spaces
factor(d::AbstractProductSpace,k) = factors(d)[k]


isambiguous(A::TensorSpace) = isambiguous(A.spaces[1]) || isambiguous(A.spaces[2])


Base.transpose(d::TensorSpace) = TensorSpace(d.spaces[2],d.spaces[1])





## Transforms

for (plan, plan!, Typ) in ((:plan_transform, :plan_transform!, :TransformPlan),
                           (:plan_itransform, :plan_itransform!, :ITransformPlan))
    @eval begin
        $plan!(S::TensorSpace, M::AbstractMatrix) = $Typ(S,(($plan(S.spaces[1],size(M,1)),size(M,1)),
                                                             ($plan(S.spaces[2],size(M,2)),size(M,2))),
                                                             Val{true})

        function *(T::$Typ{<:Any,<:TensorSpace,true}, M::AbstractMatrix)
            n=size(M,1)

            for k=1:size(M,2)
                M[:,k]=T.plan[1][1]*M[:,k]
            end
            for k=1:n
                M[k,:]=T.plan[2][1]*M[k,:]
            end
            M
        end

        function *(T::$Typ{TT,SS,false},v::AbstractVector) where {SS<:TensorSpace,TT}
            P = $Typ(T.space,T.plan,Val{true})
            P*AbstractVector{rangetype(SS)}(v)
        end
    end
end

function plan_transform(sp::TensorSpace, ::Type{T}, n::Integer) where {T}
    NM=n
    if isfinite(dimension(sp.spaces[1])) && isfinite(dimension(sp.spaces[2]))
        N,M=dimension(sp.spaces[1]),dimension(sp.spaces[2])
    elseif isfinite(dimension(sp.spaces[1]))
        N=dimension(sp.spaces[1])
        M=NM÷N
    elseif isfinite(dimension(sp.spaces[2]))
        M=dimension(sp.spaces[2])
        N=NM÷M
    else
        N=M=round(Int,sqrt(n))
    end

    TransformPlan(sp,((plan_transform(sp.spaces[1],T,N),N),
                    (plan_transform(sp.spaces[2],T,M),M)),
                Val{false})
end

function plan_transform!(sp::TensorSpace, ::Type{T}, n::Integer) where {T}
    P = plan_transform(sp, T, n)
    TransformPlan(sp, P.plan, Val{true})
end

plan_transform(sp::TensorSpace, v::AbstractVector) = plan_transform(sp,eltype(v),length(v))
plan_transform!(sp::TensorSpace, v::AbstractVector) = plan_transform!(sp,eltype(v),length(v))

function plan_itransform(sp::TensorSpace, v::AbstractVector{T}) where {T}
    N,M = size(totensor(sp, v)) # wasteful
    ITransformPlan(sp,((plan_itransform(sp.spaces[1],T,N),N),
                    (plan_itransform(sp.spaces[2],T,M),M)),
                Val{false})
end


function *(T::TransformPlan{TT,<:TensorSpace,true},v::AbstractVector) where TT # need where TT
    N,M = T.plan[1][2],T.plan[2][2]
    V=reshape(v,N,M)
    fromtensor(T.space,T*V)
end

*(T::ITransformPlan{TT,<:TensorSpace,true},v::AbstractVector) where TT  =
    vec(T*totensor(T.space,v))


## points

points(d::Union{EuclideanDomain{2},BivariateSpace},n,m) = points(d,n,m,1),points(d,n,m,2)

function points(d::BivariateSpace,n,m,k)
    ptsx=points(columnspace(d,1),n)
    ptst=points(factor(d,2),m)

    promote_type(eltype(ptsx),eltype(ptst))[fromcanonical(d,x,t)[k] for x in ptsx, t in ptst]
end




##  Fun routines

fromtensor(S::Space,M::AbstractMatrix) = fromtensor(tensorizer(S),M)
totensor(S::Space,M::AbstractVector) = totensor(tensorizer(S),M)

# we only copy upper triangular of coefficients
function fromtensor(it::Tensorizer,M::AbstractMatrix)
    n,m=size(M)
    ret=zeros(eltype(M),blockstop(it,max(n,m)))
    k = 1
    for (K,J) in it
        if k > length(ret)
            break
        end
        if K ≤ n && J ≤ m
            ret[k] = M[K,J]
        end
        k += 1
    end
    ret
end


function totensor(it::Tensorizer,M::AbstractVector)
    n=length(M)
    B=block(it,n)
    ds = dimensions(it)

    ret=zeros(eltype(M),sum(it.blocks[1][1:min(B.n[1],length(it.blocks[1]))]),
                        sum(it.blocks[2][1:min(B.n[1],length(it.blocks[2]))]))
    k=1
    for (K,J) in it
        if k > n
            break
        end
        ret[K,J] = M[k]
        k += 1
    end
    ret
end

for OP in (:block,:blockstart,:blockstop)
    @eval begin
        $OP(s::TensorSpace, ::PosInfinity) = ℵ₀
        $OP(s::TensorSpace, M::Block) = $OP(tensorizer(s),M)
        $OP(s::TensorSpace, M) = $OP(tensorizer(s),M)
    end
end

function points(sp::TensorSpace,n)
    pts=Array{float(eltype(domain(sp)))}(undef,0)
    a,b = sp.spaces
    if isfinite(dimension(a)) && isfinite(dimension(b))
        N,M=dimension(a),dimension(b)
    elseif isfinite(dimension(a))
        N=dimension(a)
        M=n÷N
    elseif isfinite(dimension(b))
        M=dimension(b)
        N=n÷M
    else
        N=M=round(Int,sqrt(n))
    end

    for y in points(b,M),
        x in points(a,N)
        push!(pts,Vec(x...,y...))
    end
    pts
end


itransform(sp::TensorSpace,cfs) = vec(itransform!(sp,coefficientmatrix(Fun(sp,cfs))))

evaluate(f::AbstractVector,S::AbstractProductSpace,x) = ProductFun(totensor(S,f),S)(x...)
evaluate(f::AbstractVector,S::AbstractProductSpace,x,y) = ProductFun(totensor(S,f),S)(x,y)



coefficientmatrix(f::Fun{<:AbstractProductSpace}) = totensor(space(f),f.coefficients)



#TODO: Implement
# function ∂(d::TensorSpace{<:IntervalOrSegment{Float64}})
#     @assert length(d.spaces) ==2
#     PiecewiseSpace([d[1].a+im*d[2],d[1].b+im*d[2],d[1]+im*d[2].a,d[1]+im*d[2].b])
# end


union_rule(a::TensorSpace,b::TensorSpace) = TensorSpace(map(union,a.spaces,b.spaces))



## Convert from 1D to 2D


# function isconvertible{T,TT}(sp::Space{Segment{Vec{2,TT}},<:Real},ts::TensorSpace)
#     d1 = domain(sp)
#     d2 = domain(ts)
#     if d2
#     length(ts.spaces) == 2 &&
#     ((domain(ts)[1] == Point(0.0) && isconvertible(sp,ts.spaces[2])) ||
#      (domain(ts)[2] == Point(0.0) && isconvertible(sp,ts.spaces[1])))
#  end

isconvertible(sp::UnivariateSpace,ts::TensorSpace{SV,D,R}) where {SV,D<:EuclideanDomain{2},R} = length(ts.spaces) == 2 &&
    ((domain(ts)[1] == Point(0.0) && isconvertible(sp,ts.spaces[2])) ||
     (domain(ts)[2] == Point(0.0) && isconvertible(sp,ts.spaces[1])))


# coefficients(f::AbstractVector,sp::ConstantSpace,ts::TensorSpace{SV,D,R}) where {SV,D<:EuclideanDomain{2},R} =
#     f[1]*ones(ts).coefficients

#
# function coefficients(f::AbstractVector,sp::Space{IntervalOrSegment{Vec{2,TT}}},ts::TensorSpace{Tuple{S,V},D,R}) where {S,V<:ConstantSpace,D<:EuclideanDomain{2},R,TT} where {T<:Number}
#     a = domain(sp)
#     b = domain(ts)
#     # make sure we are the same domain. This will be replaced by isisomorphic
#     @assert first(a) ≈ Vec(first(factor(b,1)),factor(b,2).x) &&
#         last(a) ≈ Vec(last(factor(b,1)),factor(b,2).x)
#
#     coefficients(f,sp,setdomain(factor(ts,1),a))
# end


function coefficients(f::AbstractVector,sp::UnivariateSpace,ts::TensorSpace{SV,D,R}) where {SV,D<:EuclideanDomain{2},R}
    @assert length(ts.spaces) == 2

    if factor(domain(ts),1) == Point(0.0)
        coefficients(f,sp,ts.spaces[2])
    elseif factor(domain(ts),2) == Point(0.0)
        coefficients(f,sp,ts.spaces[1])
    else
        error("Cannot convert coefficients from $sp to $ts")
    end
end


function isconvertible(sp::Space{Segment{Vec{2,TT}}},ts::TensorSpace{SV,D,R}) where {TT,SV,D<:EuclideanDomain{2},R}
    d1 = domain(sp)
    d2 = domain(ts)
    if length(ts.spaces) ≠ 2
        return false
    end
    if d1.a[2] ≈ d1.b[2]
        isa(factor(d2,2),Point) && factor(d2,2).x ≈ d1.a[2] &&
            isconvertible(setdomain(sp,Segment(d1.a[1],d1.b[1])),ts[1])
    elseif d1.a[1] ≈ d1.b[1]
        isa(factor(d2,1),Point) && factor(d2,1).x ≈ d1.a[1] &&
            isconvertible(setdomain(sp,Segment(d1.a[2],d1.b[2])),ts[2])
    else
        return false
    end
end


function coefficients(f::AbstractVector,sp::Space{Segment{Vec{2,TT}}},
                            ts::TensorSpace{SV,D,R}) where {TT,SV,D<:EuclideanDomain{2},R}
    @assert length(ts.spaces) == 2
    d1 = domain(sp)
    d2 = domain(ts)
    if d1.a[2] ≈ d1.b[2]
        coefficients(f,setdomain(sp,Segment(d1.a[1],d1.b[1])),factor(ts,1))
    elseif d1.a[1] ≈ d1.b[1]
        coefficients(f,setdomain(sp,Segment(d1.a[2],d1.b[2])),factor(ts,2))
    else
        error("Cannot convert coefficients from $sp to $ts")
    end
end




Fun(::typeof(identity), S::TensorSpace) = Fun(xyz->collect(xyz),S)
