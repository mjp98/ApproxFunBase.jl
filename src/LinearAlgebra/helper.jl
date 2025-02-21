import Base: chop

# BLAS/linear algebra overrides

@inline dot(x...) = LinearAlgebra.dot(x...)
@inline dot(M::Int,a::Ptr{T},incx::Int,b::Ptr{T},incy::Int) where {T<:Union{Float64,Float32}} =
    BLAS.dot(M,a,incx,b,incy)
@inline dot(M::Int,a::Ptr{T},incx::Int,b::Ptr{T},incy::Int) where {T<:Union{ComplexF64,ComplexF32}} =
    BLAS.dotc(M,a,incx,b,incy)

dotu(f::StridedVector{T},g::StridedVector{T}) where {T<:Union{ComplexF32,ComplexF64}} =
    BLAS.dotu(f,g)
dotu(f::AbstractVector{Complex{Float64}},g::AbstractVector{N}) where {N<:Real} = dot(conj(f),g)
dotu(f::AbstractVector{N},g::AbstractVector{T}) where {N<:Real,T<:Number} = dot(f,g)


normalize!(w::AbstractVector) = rmul!(w,inv(norm(w)))
normalize!(w::Vector{T}) where {T<:BlasFloat} = normalize!(length(w),w)
normalize!(n,w::Union{Vector{T},Ptr{T}}) where {T<:Union{Float64,Float32}} =
    BLAS.scal!(n,inv(BLAS.nrm2(n,w,1)),w,1)
normalize!(n,w::Union{Vector{T},Ptr{T}}) where {T<:Union{ComplexF64,ComplexF32}} =
    BLAS.scal!(n,T(inv(BLAS.nrm2(n,w,1))),w,1)


flipsign(x,y) = Base.flipsign(x,y)
flipsign(x,y::Complex) = y==0 ? x : x*sign(y)

# Used for spaces not defined yet
struct UnsetNumber <: Number  end
promote_rule(::Type{UnsetNumber},::Type{N}) where {N<:Number} = N
promote_rule(::Type{Bool}, ::Type{UnsetNumber}) = Bool

# Test the number of arguments a function takes
hasnumargs(f,k) = k == 1 ? applicable(f, 0.0) : applicable(f, (1.0:k)...)

# fast implementation of isapprox with atol a non-keyword argument in most cases
isapprox_atol(a,b,atol;kwds...) = isapprox(a,b;atol=atol,kwds...)
isapprox_atol(a::Vec,b::Vec,atol::Real=0;kwds...) = isapprox_atol(collect(a),collect(b),atol;kwds...)
function isapprox_atol(x::Number, y::Number, atol::Real=0; rtol::Real=Base.rtoldefault(x,y))
    x == y || (isfinite(x) && isfinite(y) && abs(x-y) <= atol + rtol*max(abs(x), abs(y)))
end
function isapprox_atol(x::AbstractArray{T}, y::AbstractArray{S},atol::Real=0; rtol::Real=Base.rtoldefault(T,S), norm::Function=vecnorm) where {T<:Number,S<:Number}
    d = norm(x - y)
    if isfinite(d)
        return d <= atol + rtol*max(norm(x), norm(y))
    else
        # Fall back to a component-wise approximate comparison
        return all(ab -> isapprox(ab[1], ab[2]; rtol=rtol, atol=atol), zip(x, y))
    end
end

# The second case handles zero
isapproxinteger(x) = isapprox(x,round(Int,x))  || isapprox(x+1,round(Int,x+1))


# This creates ApproxFunBase.real, ApproxFunBase.eps and ApproxFunBase.dou
# which we override for default julia types
real(x...) = Base.real(x...)
real(::Type{UnsetNumber}) = UnsetNumber
real(::Type{Array{T,n}}) where {T<:Real,n} = Array{T,n}
real(::Type{Array{T,n}}) where {T<:Complex,n} = Array{real(T),n}
real(::Type{Vec{N,T}}) where {N,T<:Real} = Vec{N,T}
real(::Type{Vec{N,T}}) where {N,T<:Complex} = Vec{N,real(T)}

float(x) = Base.float(x)
Base.float(::UnsetNumber) = UnsetNumber()
Base.float(::Type{UnsetNumber}) = UnsetNumber
float(::Type{Array{T,N}}) where {T,N} = Array{float(T),N}
float(::Type{SVector{N,T}}) where {T,N} = SVector{N,float(T)}



eps(x...) = Base.eps(x...)
eps(x) = Base.eps(x)

eps(::Type{T}) where T<:Integer = zero(T)
eps(::Type{T}) where T<:Rational = zero(T)
eps(::T) where T<:Integer = eps(T)

eps(::Type{Complex{T}}) where {T<:Real} = eps(real(T))
eps(z::Complex{T}) where {T<:Real} = eps(abs(z))
eps(::Type{Dual{Complex{T}}}) where {T<:Real} = eps(real(T))
eps(z::Dual{Complex{T}}) where {T<:Real} = eps(abs(z))


eps(::Type{Vector{T}}) where {T<:Number} = eps(T)
eps(::Type{Vec{k,T}}) where {k,T<:Number} = eps(T)


isnan(x) = Base.isnan(x)
isnan(x::Vec) = map(isnan,x)


# BLAS


# implement muladd default
muladd(a,b,c) = a*b+c
muladd(a::Number,b::Number,c::Number) = Base.muladd(a,b,c)


for TYP in (:Float64,:Float32,:ComplexF64,:ComplexF32)
    @eval scal!(n::Integer,cst::$TYP,ret::DenseArray{T},k::Integer) where {T<:$TYP} =
            BLAS.scal!(n,cst,ret,k)
end


scal!(n::Integer,cst::BlasFloat,ret::DenseArray{T},k::Integer) where {T<:BlasFloat} =
    BLAS.scal!(n,convert(T,cst),ret,k)

function scal!(n::Integer,cst::Number,ret::AbstractArray,k::Integer)
    @assert k*n ≤ length(ret)
    @simd for j=1:k:k*(n-1)+1
        @inbounds ret[j] *= cst
    end
    ret
end

scal!(cst::Number,v::AbstractArray) = scal!(length(v),cst,v,1)



# Helper routines

function reverseeven!(x::AbstractVector)
    n = length(x)
    if iseven(n)
        @inbounds @simd for k=2:2:n÷2
            x[k],x[n+2-k] = x[n+2-k],x[k]
        end
    else
        @inbounds @simd for k=2:2:n÷2
            x[k],x[n+1-k] = x[n+1-k],x[k]
        end
    end
    x
end

function negateeven!(x::AbstractVector)
    @inbounds @simd for k = 2:2:length(x)
        x[k] *= -1
    end
    x
end

#checkerboard, same as applying negativeeven! to all rows then all columns
function negateeven!(X::AbstractMatrix)
    for j = 1:2:size(X,2)
        @inbounds @simd for k = 2:2:size(X,1)
            X[k,j] *= -1
        end
    end
    for j = 2:2:size(X,2)
        @inbounds @simd for k = 1:2:size(X,1)
            X[k,j] *= -1
        end
    end
    X
end

const alternatesign! = negateeven!

alternatesign(v::AbstractVector) = alternatesign!(copy(v))

alternatingvector(n::Integer) = 2*mod([1:n],2) .- 1

function alternatingsum(v::AbstractVector)
    ret = zero(eltype(v))
    s = 1
    @inbounds for k=1:length(v)
        ret+=s*v[k]
        s*=-1
    end

    ret
end

# Sum Hadamard product of vectors up to minimum over lengths
function mindotu(a::AbstractVector,b::AbstractVector)
    ret,m = zero(promote_type(eltype(a),eltype(b))),min(length(a),length(b))
    @inbounds @simd for i=m:-1:1 ret += a[i]*b[i] end
    ret
end


# efficiently resize a Matrix.  Note it doesn't change the input ptr
function unsafe_resize!(W::AbstractMatrix,::Colon,m::Integer)
    if m == size(W,2)
        W
    else
        n=size(W,1)
        reshape(resize!(vec(W),n*m),n,m)
    end
end

function unsafe_resize!(W::AbstractMatrix,n::Integer,::Colon)
    N=size(W,1)
    if n == N
        W
    elseif n < N
        W[1:n,:]
    else
        m=size(W,2)
        ret=Matrix{eltype(W)}(n,m)
        ret[1:N,:] = W
        ret
    end
end

function unsafe_resize!(W::AbstractMatrix,n::Integer,m::Integer)
    N=size(W,1)
    if n == N
        unsafe_resize!(W,:,m)
    else
        unsafe_resize!(unsafe_resize!(W,n,:),:,m)
    end
end


function pad!(f::AbstractVector{T},n::Integer) where T
	if n > length(f)
		append!(f,zeros(T,n - length(f)))
	else
		resize!(f,n)
	end
end


function pad(f::AbstractVector{T},n::Integer) where T
	if n > length(f)
	   ret=Vector{T}(undef, n)
	   ret[1:length(f)]=f
	   for j=length(f)+1:n
	       ret[j]=zero(T)
	   end
       ret
	else
        f[1:n]
	end
end

function pad(f::AbstractVector{Any},n::Integer)
	if n > length(f)
        Any[f...,zeros(n - length(f))...]
	else
        f[1:n]
	end
end

pad(x::Number, n::Int) = [x; zeros(typeof(x), n-1)]

function pad(v::AbstractVector,n::Integer,m::Integer)
    @assert m==1
    pad(v,n)
end

function pad(A::AbstractMatrix,n::Integer,m::Integer)
    T=eltype(A)
	if n <= size(A,1) && m <= size(A,2)
        A[1:n,1:m]
	elseif n==0 || m==0
	   Matrix{T}(undef,n,m)  #fixes weird julia bug when T==None
    else
        ret = Matrix{T}(undef,n,m)
        minn=min(n,size(A,1))
        minm=min(m,size(A,2))
        for k=1:minn,j=1:minm
            @inbounds ret[k,j]=A[k,j]
        end
        for k=minn+1:n,j=1:minm
            @inbounds ret[k,j]=zero(T)
        end
        for k=1:n,j=minm+1:m
            @inbounds ret[k,j]=zero(T)
        end
        for k=minn+1:n,j=minm+1:m
            @inbounds ret[k,j]=zero(T)
        end

        ret
	end
end

pad(A::AbstractMatrix,::Colon,m::Integer) = pad(A,size(A,1),m)
pad(A::AbstractMatrix,n::Integer,::Colon) = pad(A,n,size(A,2))


function pad(v, ::PosInfinity)
    if isinf(length(v))
        v
    else
        Vcat(v, Zeros{Int}(∞))
    end
end

function pad(v::AbstractVector{T}, ::PosInfinity) where T
    if isinf(length(v))
        v
    else
        Vcat(v, Zeros{T}(∞))
    end
end

_pad!!(::Val{false}) = pad
_pad!!(::Val{true}) = pad!

#TODO:padleft!

function padleft(f::AbstractVector,n::Integer)
	if (n > length(f))
        [zeros(n - length(f)); f]
	else
        f[end-n+1:end]
	end
end



##chop!
function chop!(c::AbstractVector,tol::Real)
    @assert tol >= 0

    for k=length(c):-1:1
        if abs(c[k]) > tol
            resize!(c,k)
            return c
        end
    end

    resize!(c,0)
    c
end

chop(f::AbstractVector,tol) = chop!(copy(f),tol)
chop!(f::AbstractVector) = chop!(f,eps())


function chop!(A::AbstractArray,tol)
    for k=size(A,1):-1:1
        if norm(A[k,:])>tol
            A=A[1:k,:]
            break
        end
    end
    for k=size(A,2):-1:1
        if norm(A[:,k])>tol
            A=A[:,1:k]
            break
        end
    end
    return A
end
chop(A::AbstractArray,tol)=chop!(A,tol)#replace by chop!(copy(A),tol) when chop! is actually in-place.



## interlace



function interlace(v::Union{Vector{Any},Tuple})
    #determine type
    T=Float64
    for vk in v
        if isa(vk,Vector{Complex{Float64}})
            T=Complex{Float64}
        end
    end
    b=Vector{Vector{T}}(undef, length(v))
    for k=1:length(v)
        b[k]=v[k]
    end
    interlace(b)
end

function interlace(a::AbstractVector{S},b::AbstractVector{V}) where {S<:Number,V<:Number}
    na=length(a);nb=length(b)
    T=promote_type(S,V)
    if nb≥na
        ret=zeros(T,2nb)
        ret[1:2:1+2*(na-1)]=a
        ret[2:2:end]=b
        ret
    else
        ret=zeros(T,2na-1)
        ret[1:2:end]=a
        if !isempty(b)
            ret[2:2:2+2*(nb-1)]=b
        end
        ret
    end
end

function interlace(a::AbstractVector,b::AbstractVector)
    na=length(a);nb=length(b)
    T=promote_type(eltype(a),eltype(b))
    if nb≥na
        ret=Vector{T}(undef, 2nb)
        ret[1:2:1+2*(na-1)]=a
        ret[2:2:end]=b
        ret
    else
        ret=Vector{T}(undef, 2na-1)
        ret[1:2:end]=a
        if !isempty(b)
            ret[2:2:2+2*(nb-1)]=b
        end
        ret
    end
end


### In-place O(n) interlacing

function highestleader(n::Int)
    i = 1
    while 3i < n i *= 3 end
    i
end

function nextindex(i::Int,n::Int)
    i <<= 1
    while i > n
        i -= n + 1
    end
    i
end

function cycle_rotate!(v::AbstractVector, leader::Int, it::Int, twom::Int)
    i = nextindex(leader, twom)
    while i != leader
        idx1, idx2 = it + i - 1, it + leader - 1
        @inbounds v[idx1], v[idx2] = v[idx2], v[idx1]
        i = nextindex(i, twom)
    end
    v
end

function right_cyclic_shift!(v::AbstractVector, it::Int, m::Int, n::Int)
    itpm = it + m
    itpmm1 = itpm - 1
    itpmpnm1 = itpmm1 + n
    reverse!(v, itpm, itpmpnm1)
    reverse!(v, itpm, itpmm1 + m)
    reverse!(v, itpm + m, itpmpnm1)
    v
end

"""
This function implements the algorithm described in:

    P. Jain, "A simple in-place algorithm for in-shuffle," arXiv:0805.1598, 2008.
"""
function interlace!(v::AbstractVector,offset::Int)
    N = length(v)
    if N < 2 + offset
        return v
    end

    it = 1 + offset
    m = 0
    n = 1

    while m < n
        twom = N + 1 - it
        h = highestleader(twom)
        m = h > 1 ? h÷2 : 1
        n = twom÷2

        right_cyclic_shift!(v,it,m,n)

        leader = 1
        while leader < 2m
            cycle_rotate!(v, leader, it, 2m)
            leader *= 3
        end

        it += 2m
    end
    v
end

## slnorm gives the norm of a slice of a matrix

function slnorm(u::AbstractMatrix,r::AbstractRange,::Colon)
    ret = zero(real(eltype(u)))
    for k=r
        @simd for j=1:size(u,2)
            #@inbounds
            ret=max(norm(u[k,j]),ret)
        end
    end
    ret
end


function slnorm(m::AbstractMatrix,kr::AbstractRange,jr::AbstractRange)
    ret=zero(real(eltype(m)))
    for j=jr
        nrm=zero(real(eltype(m)))
        for k=kr
            @inbounds nrm+=abs2(m[k,j])
        end
        ret=max(sqrt(nrm),ret)
    end
    ret
end

slnorm(m::AbstractMatrix,kr::AbstractRange,jr::Integer) = slnorm(m,kr,jr:jr)
slnorm(m::AbstractMatrix,kr::Integer,jr::AbstractRange) = slnorm(m,kr:kr,jr)


function slnorm(B::BandedMatrix{T},r::AbstractRange,::Colon) where T
    ret = zero(real(T))
    m=size(B,2)
    for k=r
        @simd for j=max(1,k-B.l):min(k+B.u,m)
            #@inbounds
            ret=max(norm(B[k,j]),ret)
        end
    end
    ret
end


slnorm(m::AbstractMatrix,k::Integer,::Colon) = slnorm(m,k,1:size(m,2))
slnorm(m::AbstractMatrix,::Colon,j::Integer) = slnorm(m,1:size(m,1),j)


## Infinity



Base.isless(x::Block{1}, y::PosInfinity) = isless(Int(x), y)
Base.isless(x::PosInfinity, y::Block{1}) = isless(x, Int(y))


## BandedMatrix



pad!(A::BandedMatrix,n,::Colon) = pad!(A,n,n+A.u)  # Default is to get all columns
columnrange(A,row::Integer) = max(1,row-bandwidth(A,1)):row+bandwidth(A,2)



## Store iterator
mutable struct CachedIterator{T,IT}
    iterator::IT
    storage::Vector{T}
    state
    length::Int
end

CachedIterator{T,IT}(it::IT, state) where {T,IT} = CachedIterator{T,IT}(it,T[],state,0)
CachedIterator(it::IT) where IT = CachedIterator{eltype(it),IT}(it, ())

function resize!(it::CachedIterator,n::Integer)
    m = it.length
    if n > m
        if n > length(it.storage)
            resize!(it.storage,2n)
        end

        @inbounds for k = m+1:n
            xst = iterate(it.iterator,it.state...)
            if xst == nothing
                it.length = k-1
                return it
            end
            it.storage[k] = xst[1]
            it.state = (xst[2],)
        end

        it.length = n
    end
    it
end


eltype(it::CachedIterator{T}) where {T} = T

iterate(it::CachedIterator) = iterate(it,1)
function iterate(it::CachedIterator,st::Int)
    if  st == it.length + 1 && iterate(it.iterator,it.state...) == nothing
        nothing
    else
        (it[st],st+1)
    end
end

function getindex(it::CachedIterator, k)
    mx = maximum(k)
    if mx > length(it) || mx < 1
        throw(BoundsError(it,k))
    end
    resize!(it,isempty(k) ? 0 : mx).storage[k]
end

function findfirst(f::Function,A::CachedIterator)
    k=1
    for c in A
        if f(c)
            return k
        end
        k+=1
    end
    return 0
end

function findfirst(A::CachedIterator,x)
    k=1
    for c in A
        if c == x
            return k
        end
        k+=1
    end
    return 0
end

length(A::CachedIterator) = length(A.iterator)

## nocat
vnocat(A...) = Base.vect(A...)
hnocat(A...) = Base.typed_hcat(mapreduce(typeof,promote_type,A),A...)
hvnocat(rows,A...) = Base.typed_hvcat(mapreduce(typeof,promote_type,A),rows,A...)
macro nocat(x)
    ex = expand(x)
    if ex.args[1] == :vcat
        ex.args[1] = :(ApproxFunBase.vnocat)
    elseif ex.args[1] == :hcat
        ex.args[1] = :(ApproxFunBase.hnocat)
    else
        @assert ex.args[1] == :hvcat
        ex.args[1] = :(ApproxFunBase.hvnocat)
    end
    esc(ex)
end



## Dynamic functions

struct DFunction{F} <: Function
    f :: F
end
(f::DFunction)(args...) = f.f(args...)

hasnumargs(f::DFunction, k) = hasnumargs(f.f, k)

dynamic(f) = f
dynamic(f::Function) = DFunction(f) # Assume f has to compile every time


# Matrix inputs




## conv

conv(x::AbstractVector, y::AbstractVector) = DSP.conv(x, y)
@generated function conv(x::SVector{N}, y::SVector{M}) where {N,M}
    NM = N+M-1
    quote
        convert(SVector{$NM}, DSP.conv(Vector(x), Vector(y)))
    end
end

conv(x::SVector{1}, y::SVector{1}) = x.*y
conv(x::AbstractVector, y::SVector{1}) = x*y[1]
conv(y::SVector{1}, x::AbstractVector) = y[1]*x
conv(x::AbstractFill, y::SVector{1}) = x*y[1]
conv(y::SVector{1}, x::AbstractFill) = y[1]*x
conv(x::AbstractFill, y::AbstractFill) = DSP.conv(x, y)


## BlockInterlacer
# interlaces coefficients by blocks
# this has the property that all the coefficients of a block of a subspace
# are grouped together, starting with the first bloc
#
# TODO: cache sums


struct BlockInterlacer{DMS<:Tuple}
    blocks::DMS
end


const TrivialInterlacer{d} = BlockInterlacer{NTuple{d,<:Ones}}

BlockInterlacer(v::AbstractVector) = BlockInterlacer(tuple(v...))

Base.eltype(it::BlockInterlacer) = Tuple{Int,Int}

dimensions(b::BlockInterlacer) = map(sum,b.blocks)
dimension(b::BlockInterlacer,k) = sum(b.blocks[k])
Base.length(b::BlockInterlacer) = mapreduce(sum,+,b.blocks)


# the state is always (whichblock,curblock,cursubblock,curcoefficients)
# start(it::BlockInterlacer) = (1,1,map(start,it.blocks),ntuple(zero,length(it.blocks)))



# are all Ints, so finite dimensional
function done(it::BlockInterlacer,st)
    for k=1:length(it.blocks)
        if st[end][k] < sum(it.blocks[k])
            return false
        end
    end
    return true
end

iterate(it::BlockInterlacer) =
    iterate(it, (1,1,ntuple(_ -> tuple(), length(it.blocks)),
            ntuple(zero,length(it.blocks))))

function iterate(it::BlockInterlacer, (N,k,blkst,lngs))
    done(it, (N,k,blkst,lngs)) && return nothing

    if N > length(it.blocks)
        # increment to next block
        blkst = map(function(blit,blst)
                xblst = iterate(blit, blst...)
                xblst == nothing ? blst : (xblst[2],)
            end,it.blocks,blkst)
        return iterate(it,(1,1,blkst,lngs))
    end

    Bnxtb = iterate(it.blocks[N],blkst[N]...)  # B is block size

    if Bnxtb == nothing
        # increment to next N
        return iterate(it,(N+1,1,blkst,lngs))
    end

    B,nxtb = Bnxtb

    if k > B
        #increment to next N
        return iterate(it,(N+1,1,blkst,lngs))
    end


    lngs = tuple(lngs[1:N-1]...,lngs[N]+1,lngs[N+1:end]...)
    return (N,lngs[N]),(N,k+1,blkst,lngs)
end

cache(Q::BlockInterlacer) = CachedIterator(Q)
