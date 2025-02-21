export Operator
export bandwidths, bandrange, \, periodic
export neumann
export ldirichlet,rdirichlet,lneumann,rneumann
export ldiffbc,rdiffbc,diffbcs
export domainspace,rangespace

const VectorIndices = Union{AbstractRange, Colon}
const IntOrVectorIndices = Union{Integer, VectorIndices}

abstract type Operator{T} end #T is the entry type, Float64 or Complex{Float64}

eltype(::Operator{T}) where {T} = T
eltype(::Type{<:Operator{T}}) where {T} = T
eltype(::Type{OT}) where {OT<:Operator} = eltype(supertype(OT))


# default entry type
# we assume entries depend on both the domain and the basis
# realdomain case doesn't use


prectype(sp::Space) = promote_type(prectype(domaintype(sp)),eltype(rangetype(sp)))

 #Operators are struct
copy(A::Operator) = A


BroadcastStyle(::Type{<:Operator}) = DefaultArrayStyle{2}()
broadcastable(A::Operator) = A

## We assume operators are T->T
rangespace(A::Operator) = error("Override rangespace for $(typeof(A))")
domainspace(A::Operator) = error("Override domainspace for $(typeof(A))")
spaces(A::Operator) = (rangespace(A), domainspace(A)) # order is consistent with size(::Matrix)
domain(A::Operator) = domain(domainspace(A))


isconstspace(_) = false
## Functionals
isafunctional(A::Operator)::Bool = size(A,1)==1 && isconstspace(rangespace(A))


isonesvec(A) = A isa AbstractFill && getindex_value(A) == 1
# block lengths of a space are 1
hastrivialblocks(A::Space) = isonesvec(blocklengths(A))
hastrivialblocks(A::Operator) = hastrivialblocks(domainspace(A)) &&
                                hastrivialblocks(rangespace(A))

# blocklengths are constant lengths
hasconstblocks(A::Space) = isa(blocklengths(A),AbstractFill)
hasconstblocks(A::Operator) = hasconstblocks(domainspace(A)) && hasconstblocks(rangespace(A)) &&
                                getindex_value(blocklengths(domainspace(A))) == getindex_value(blocklengths(rangespace(A)))


macro functional(FF)
    quote
        Base.size(A::$FF,k::Integer) = k==1 ? 1 : dimension(domainspace(A))
        ApproxFunBase.rangespace(F::$FF) = ConstantSpace(eltype(F))
        ApproxFunBase.isafunctional(::$FF) = true
        ApproxFunBase.blockbandwidths(A::$FF) = 0,hastrivialblocks(domainspace(A)) ? bandwidth(A,2) : ℵ₀
        function ApproxFunBase.defaultgetindex(f::$FF,k::Integer,j::Integer)
            @assert k==1
            f[j]::eltype(f)
        end
        function ApproxFunBase.defaultgetindex(f::$FF,k::Integer,j::AbstractRange)
            @assert k==1
            f[j]
        end
        function ApproxFunBase.defaultgetindex(f::$FF,k::Integer,j)
            @assert k==1
            f[j]
        end
        function ApproxFunBase.defaultgetindex(f::$FF,k::AbstractRange,j::Integer)
            @assert k==1:1
            f[j]
        end
        function ApproxFunBase.defaultgetindex(f::$FF,k::AbstractRange,j::AbstractRange)
            @assert k==1:1
            reshape(f[j],1,length(j))
        end
        function ApproxFunBase.defaultgetindex(f::$FF,k::AbstractRange,j)
            @assert k==1:1
            reshape(f[j],1,length(j))
        end
    end
end


blocksize(A::Operator,k) = k==1 ? length(blocklengths(rangespace(A))) : length(blocklengths(domainspace(A)))
blocksize(A::Operator) = (blocksize(A,1),blocksize(A,2))


Base.size(A::Operator) = (size(A,1),size(A,2))
Base.size(A::Operator,k::Integer) = k==1 ? dimension(rangespace(A)) : dimension(domainspace(A))
Base.length(A::Operator) = size(A,1) * size(A,2)


# used to compute "end" for last index
function lastindex(A::Operator, n::Integer)
    if n > 2
        1
    elseif n==2
        size(A,2)
    elseif isinf(size(A,2)) || isinf(size(A,1))
        ℵ₀
    else
        size(A,1)
    end
end
lastindex(A::Operator) = size(A,1)*size(A,2)

Base.ndims(::Operator) = 2






## bandrange and indexrange
isbandedbelow(A::Operator) = isfinite(bandwidth(A,1))
isbandedabove(A::Operator) = isfinite(bandwidth(A,2))
isbanded(A::Operator) = isbandedbelow(A) && isbandedabove(A)


isbandedblockbandedbelow(_) = false
isbandedblockbandedabove(_) = false

isbandedblockbanded(A::Operator) = isbandedblockbandedabove(A) && isbandedblockbandedbelow(A)


# this should be determinable at compile time
#TODO: I think it can be generalized to the case when the domainspace
# blocklengths == rangespace blocklengths, in which case replace the definition
# of p with maximum(blocklength(domainspace(A)))
function blockbandwidths(A::Operator)
    hastrivialblocks(A) && return bandwidths(A)

    if hasconstblocks(A)
        a,b = bandwidths(A)
        p = getindex_value(blocklengths(domainspace(A)))
        return (-fld(-a,p),-fld(-b,p))
    end

    #TODO: Generalize to finite dimensional
    if size(A,2) == 1
        rs = rangespace(A)

        if hasconstblocks(rs)
            a = bandwidth(A,1)
            p = getindex_value(blocklengths(rs))
            return (-fld(-a,p),0)
        end
    end

    return (length(blocklengths(rangespace(A)))-1,length(blocklengths(domainspace(A)))-1)
end

# assume dense blocks
subblockbandwidths(K::Operator) = maximum(blocklengths(rangespace(K)))-1, maximum(blocklengths(domainspace(K)))-1

isblockbandedbelow(A) = isfinite(blockbandwidth(A,1))
isblockbandedabove(A) = isfinite(blockbandwidth(A,2))
isblockbanded(A::Operator) = isblockbandedbelow(A) && isblockbandedabove(A)

israggedbelow(A::Operator) = isbandedbelow(A) || isbandedblockbanded(A) || isblockbandedbelow(A)


blockbandwidth(K::Operator, k::Integer) = blockbandwidths(K)[k]
subblockbandwidth(K::Operator,k::Integer) = subblockbandwidths(K)[k]


bandwidth(A::Operator, k::Integer) = bandwidths(A)[k]
# we are always banded by the size
bandwidths(A::Operator) = (size(A,1)-1,size(A,2)-1)
bandwidths(A::Operator, k::Integer) = bandwidths(A)[k]



## Strides
# lets us know if operators decouple the entries
# to split into sub problems
# A diagonal operator has essentially infinite stride
# which we represent by a factorial, so that
# the gcd with any number < 10 is the number
stride(A::Operator) =
    isdiag(A) ? factorial(10) : 1

isdiag(A::Operator) = bandwidths(A)==(0,0)
istriu(A::Operator) = bandwidth(A, 1) == 0
istril(A::Operator) = bandwidth(A, 2) == 0


## Construct operators


include("SubOperator.jl")


#
# sparse(B::Operator,n::Integer)=sparse(BandedMatrix(B,n))
# sparse(B::Operator,n::AbstractRange,m::AbstractRange)=sparse(BandedMatrix(B,n,m))
# sparse(B::Operator,n::Colon,m::AbstractRange)=sparse(BandedMatrix(B,n,m))
# sparse(B::Operator,n::AbstractRange,m::Colon)=sparse(BandedMatrix(B,n,m))

## geteindex



getindex(B::Operator,k,j) = defaultgetindex(B,k,j)
getindex(B::Operator,k) = defaultgetindex(B,k)
getindex(B::Operator,k::Block{2}) = B[Block.(k.n)...]




## override getindex.

defaultgetindex(B::Operator,k::Integer) = error("Override [k] for $(typeof(B))")
defaultgetindex(B::Operator,k::Integer,j::Integer) = error("Override [k,j] for $(typeof(B))")


# Ranges


defaultgetindex(op::Operator,kr::AbstractRange) = eltype(op)[op[k] for k in kr]
defaultgetindex(B::Operator,k::Block,j::Block) = AbstractMatrix(view(B,k,j))
defaultgetindex(B::Operator,k::AbstractRange,j::Block) = AbstractMatrix(view(B,k,j))
defaultgetindex(B::Operator,k::Block,j::AbstractRange) = AbstractMatrix(view(B,k,j))
defaultgetindex(B::Operator,k::AbstractRange,j::AbstractRange) = AbstractMatrix(view(B,k,j))

defaultgetindex(op::Operator,k::Integer,jr::AbstractRange) = eltype(op)[op[k,j] for j in jr]
defaultgetindex(op::Operator,kr::AbstractRange,j::Integer) = eltype(op)[op[k,j] for k in kr]

defaultgetindex(B::Operator,k::Block,j::BlockRange) = AbstractMatrix(view(B,k,j))
defaultgetindex(B::Operator,k::BlockRange,j::BlockRange) = AbstractMatrix(view(B,k,j))

defaultgetindex(op::Operator,k::Integer,jr::BlockRange) = eltype(op)[op[k,j] for j in jr]
defaultgetindex(op::Operator,kr::BlockRange,j::Integer) = eltype(op)[op[k,j] for k in kr]


# Colon casdes
defaultgetindex(A::Operator,kj::CartesianIndex{2}) = A[kj[1],kj[2]]
defaultgetindex(A::Operator,kj::CartesianIndex{1}) = A[kj[1]]
defaultgetindex(A::Operator,k,j) = view(A,k,j)



# TODO: finite dimensional blocks
blockcolstart(A::Operator, J::Block{1}) = Block(max(1,Int(J)-blockbandwidth(A,2)))
blockrowstart(A::Operator, K::Block{1}) = Block(max(1,Int(K)-blockbandwidth(A,1)))
blockcolstop(A::Operator, J::Block{1}) = Block(min(Int(J)+blockbandwidth(A,1),blocksize(A,1)))
blockrowstop(A::Operator, K::Block{1}) = Block(min(Int(K)+blockbandwidth(A,2),blocksize(A,2)))

blockrows(A::Operator, K::Block{1}) = blockrange(rangespace(A),K)
blockcols(A::Operator, J::Block{1}) = blockrange(domainspace(A),J)


# default is to use bandwidth
# override for other shaped operators
#TODO: Why size(A,2) in colstart?
banded_colstart(A::Operator, i::Integer) = min(max(i-bandwidth(A,2), 1), size(A, 2))
banded_colstop(A::Operator, i::Integer) = max(0,min(i+bandwidth(A,1), size(A, 1)))
banded_rowstart(A::Operator, i::Integer) = min(max(i-bandwidth(A,1), 1), size(A, 1))
banded_rowstop(A::Operator, i::Integer) = max(0,min(i+bandwidth(A,2), size(A, 2)))

blockbanded_colstart(A::Operator, i::Integer) =
        blockstart(rangespace(A), block(domainspace(A),i)-blockbandwidth(A,2))
blockbanded_colstop(A::Operator, i::Integer) =
    min(blockstop(rangespace(A), block(domainspace(A),i)+blockbandwidth(A,1)),
        size(A, 1))
blockbanded_rowstart(A::Operator, i::Integer) =
        blockstart(domainspace(A), block(rangespace(A),i)-blockbandwidth(A,1))
blockbanded_rowstop(A::Operator, i::Integer) =
    min(blockstop(domainspace(A), block(rangespace(A),i)+blockbandwidth(A,2)),
        size(A, 2))


function bandedblockbanded_colstart(A::Operator, i::Integer)
    ds = domainspace(A)
    B = block(ds,i)
    ξ = i - blockstart(ds,B) + 1  # col in block
    bs = blockstart(rangespace(A), B-blockbandwidth(A,2))
    max(bs,bs + ξ - 1 - subblockbandwidth(A,2))
end

function bandedblockbanded_colstop(A::Operator, i::Integer)
    i ≤ 0 && return 0
    ds = domainspace(A)
    rs = rangespace(A)
    B = block(ds,i)
    ξ = i - blockstart(ds,B) + 1  # col in block
    Bend = B+blockbandwidth(A,1)
    bs = blockstart(rs, Bend)
    min(blockstop(rs,Bend),bs + ξ - 1 + subblockbandwidth(A,1))
end

function bandedblockbanded_rowstart(A::Operator, i::Integer)
    rs = rangespace(A)
    B = block(rs,i)
    ξ = i - blockstart(rs,B) + 1  # row in block
    bs = blockstart(domainspace(A), B-blockbandwidth(A,1))
    max(bs,bs + ξ - 1 - subblockbandwidth(A,1))
end

function bandedblockbanded_rowstop(A::Operator, i::Integer)
    ds = domainspace(A)
    rs = rangespace(A)
    B = block(rs,i)
    ξ = i - blockstart(rs,B) + 1  # row in block
    Bend = B+blockbandwidth(A,2)
    bs = blockstart(ds, Bend)
    min(blockstop(ds,Bend),bs + ξ - 1 + subblockbandwidth(A,2))
end


unstructured_colstart(A, i) = 1
unstructured_colstop(A, i) = size(A,1)
unstructured_rowstart(A, i) = 1
unstructured_rowstop(A, i) = size(A,2)


function default_colstart(A::Operator, i::Integer)
    if isbandedabove(A)
        banded_colstart(A,i)
    elseif isbandedblockbanded(A)
        bandedblockbanded_colstart(A, i)
    elseif isblockbanded(A)
        blockbanded_colstart(A, i)
    else
        unstructured_colstart(A, i)
    end
end

function default_colstop(A::Operator, i::Integer)
    if isbandedbelow(A)
        banded_colstop(A,i)
    elseif isbandedblockbanded(A)
        bandedblockbanded_colstop(A, i)
    elseif isblockbanded(A)
        blockbanded_colstop(A, i)
    else
        unstructured_colstop(A, i)
    end
end

function default_rowstart(A::Operator, i::Integer)
    if isbandedbelow(A)
        banded_rowstart(A,i)
    elseif isbandedblockbanded(A)
        bandedblockbanded_rowstart(A, i)
    elseif isblockbanded(A)
        blockbanded_rowstart(A, i)
    else
        unstructured_rowstart(A, i)
    end
end

function default_rowstop(A::Operator, i::Integer)
    if isbandedabove(A)
        banded_rowstop(A,i)
    elseif isbandedblockbanded(A)
        bandedblockbanded_rowstop(A, i)
    elseif isblockbanded(A)
        blockbanded_rowstop(A, i)
    else
        unstructured_rowstop(A, i)
    end
end



for OP in (:colstart,:colstop,:rowstart,:rowstop)
    defOP = Meta.parse("default_"*string(OP))
    @eval begin
        $OP(A::Operator, i::Integer) = $defOP(A,i)
        $OP(A::Operator, i::PosInfinity) = ℵ₀
    end
end




function defaultgetindex(A::Operator,::Type{FiniteRange},::Type{FiniteRange})
    if isfinite(size(A,1)) && isfinite(size(A,2))
        A[1:size(A,1),1:size(A,2)]
    else
        error("Only exists for finite operators.")
    end
end

defaultgetindex(A::Operator,k::Type{FiniteRange},J::Block) = A[k,blockcols(A,J)]
function defaultgetindex(A::Operator,::Type{FiniteRange},jr::AbstractVector{Int})
    cs = (isbanded(A) || isblockbandedbelow(A)) ? colstop(A,maximum(jr)) : mapreduce(j->colstop(A,j),max,jr)
    A[1:cs,jr]
end

function defaultgetindex(A::Operator,::Type{FiniteRange},jr::BlockRange{1})
    cs = (isbanded(A) || isblockbandedbelow(A)) ? blockcolstop(A,maximum(jr)) : mapreduce(j->blockcolstop(A,j),max,jr)
    A[Block(1):cs,jr]
end

function view(A::Operator,::Type{FiniteRange},jr::AbstractVector{Int})
    cs = (isbanded(A) || isblockbandedbelow(A)) ? colstop(A,maximum(jr)) : mapreduce(j->colstop(A,j),max,jr)
    view(A,1:cs,jr)
end

function view(A::Operator,::Type{FiniteRange},jr::BlockRange{1})
    cs = (isbanded(A) || isblockbandedbelow(A)) ? blockcolstop(A,maximum(jr)) : mapreduce(j->blockcolstop(A,j),max,jr)
    view(A,Block(1):cs,jr)
end


defaultgetindex(A::Operator,K::Block,j::Type{FiniteRange}) = A[blockrows(A,K),j]
defaultgetindex(A::Operator,kr,::Type{FiniteRange}) =
    A[kr,1:rowstop(A,maximum(kr))]





## Composition with a Fun, LowRankFun, and ProductFun

getindex(B::Operator,f::Fun) = B*Multiplication(domainspace(B),f)
getindex(B::Operator,f::LowRankFun{S,M,SS,T}) where {S,M,SS,T} = mapreduce(i->f.A[i]*B[f.B[i]],+,1:rank(f))
getindex(B::Operator{BT},f::ProductFun{S,V,SS,T}) where {BT,S,V,SS,T} =
    mapreduce(i->f.coefficients[i]*B[Fun(f.space[2],[zeros(promote_type(BT,T),i-1);
                                            one(promote_type(BT,T))])],
                +,1:length(f.coefficients))



# Convenience for wrapper ops
unwrap_axpy!(α,P,A) = BLAS.axpy!(α,view(parent(P).op,P.indexes[1],P.indexes[2]),A)
iswrapper(_) = false
haswrapperstructure(_) = false

# use this for wrapper operators that have the same structure but
# not necessarily the same entries
#
#  Ex: c*op or real(op)
macro wrapperstructure(Wrap)
    ret = quote
        haswrapperstructure(::$Wrap) = true
    end

    for func in (:(ApproxFunBase.bandwidths),:(LinearAlgebra.stride),
                 :(ApproxFunBase.isbandedblockbanded),:(ApproxFunBase.isblockbanded),
                 :(ApproxFunBase.israggedbelow),:(Base.size),:(ApproxFunBase.isbanded),
                 :(ApproxFunBase.blockbandwidths),:(ApproxFunBase.subblockbandwidths),
                 :(LinearAlgebra.issymmetric))
        ret = quote
            $ret

            $func(D::$Wrap) = $func(D.op)
        end
    end

     for func in (:(ApproxFunBase.bandwidth),:(ApproxFunBase.colstart),:(ApproxFunBase.colstop),
                     :(ApproxFunBase.rowstart),:(ApproxFunBase.rowstop),:(ApproxFunBase.blockbandwidth),
                     :(Base.size),:(ApproxFunBase.subblockbandwidth))
         ret = quote
             $ret

             $func(D::$Wrap,k::Integer) = $func(D.op,k)
             $func(A::$Wrap,i::ApproxFunBase.PosInfinity) = ℵ₀ # $func(A.op,i) | see PR #42
         end
     end

    esc(ret)
end



# use this for wrapper operators that have the same entries but
# not necessarily the same spaces
#
macro wrappergetindex(Wrap)
    ret = quote
        Base.getindex(OP::$Wrap,k::Integer...) =
            OP.op[k...]::eltype(OP)

        Base.getindex(OP::$Wrap,k::Union{Number,AbstractArray,Colon}...) = OP.op[k...]
        Base.getindex(OP::$Wrap,k::ApproxFunBase.InfRanges, j::ApproxFunBase.InfRanges) = view(OP, k, j)
        Base.getindex(OP::$Wrap,k::ApproxFunBase.InfRanges, j::Colon) = view(OP, k, j)
        Base.getindex(OP::$Wrap,k::Colon, j::ApproxFunBase.InfRanges) = view(OP, k, j)
        Base.getindex(OP::$Wrap,k::Colon, j::Colon) = view(OP, k, j)

        BLAS.axpy!(α,P::ApproxFunBase.SubOperator{T,OP},A::AbstractMatrix) where {T,OP<:$Wrap} =
            ApproxFunBase.unwrap_axpy!(α,P,A)

        ApproxFunBase.mul_coefficients(A::$Wrap,b) = ApproxFunBase.mul_coefficients(A.op,b)
        ApproxFunBase.mul_coefficients(A::ApproxFunBase.SubOperator{T,OP,Tuple{UnitRange{Int},UnitRange{Int}}},b) where {T,OP<:$Wrap} =
            ApproxFunBase.mul_coefficients(view(parent(A).op,S.indexes[1],S.indexes[2]),b)
        ApproxFunBase.mul_coefficients(A::ApproxFunBase.SubOperator{T,OP},b) where {T,OP<:$Wrap} =
            ApproxFunBase.mul_coefficients(view(parent(A).op,S.indexes[1],S.indexes[2]),b)
    end

    for TYP in (:(ApproxFunBase.BandedMatrix),:(ApproxFunBase.RaggedMatrix),
                :Matrix,:Vector,:AbstractVector)
        ret = quote
            $ret

            $TYP(P::ApproxFunBase.SubOperator{T,OP}) where {T,OP<:$Wrap} =
                $TYP(view(parent(P).op,P.indexes[1],P.indexes[2]))
            $TYP(P::ApproxFunBase.SubOperator{T,OP,NTuple{2,UnitRange{Int}}}) where {T,OP<:$Wrap} =
                $TYP(view(parent(P).op,P.indexes[1],P.indexes[2]))
        end
    end

    ret = quote
        $ret

        # fast converts to banded matrices would be based on indices, not blocks
        function ApproxFunBase.BandedMatrix(S::ApproxFunBase.SubOperator{T,OP,NTuple{2,ApproxFunBase.BlockRange1}}) where {T,OP<:$Wrap}
            A = parent(S)
            ds = domainspace(A)
            rs = rangespace(A)
            KR,JR = parentindices(S)
            ApproxFunBase.BandedMatrix(view(A,
                              ApproxFunBase.blockstart(rs,first(KR)):ApproxFunBase.blockstop(rs,last(KR)),
                              ApproxFunBase.blockstart(ds,first(JR)):ApproxFunBase.blockstop(ds,last(JR))))
        end


        # if the spaces change, then we need to be smarter
        function ApproxFunBase.BlockBandedMatrix(S::ApproxFunBase.SubOperator{T,OP}) where {T,OP<:$Wrap}
            P = parent(S)
            if ApproxFunBase.blocklengths(domainspace(P)) === ApproxFunBase.blocklengths(domainspace(P.op)) &&
                    ApproxFunBase.blocklengths(rangespace(P)) === ApproxFunBase.blocklengths(rangespace(P.op))
                ApproxFunBase.BlockBandedMatrix(view(parent(S).op,S.indexes[1],S.indexes[2]))
            else
                ApproxFunBase.default_BlockBandedMatrix(S)
            end
        end

        function ApproxFunBase.PseudoBlockMatrix(S::ApproxFunBase.SubOperator{T,OP}) where {T,OP<:$Wrap}
            P = parent(S)
            if ApproxFunBase.blocklengths(domainspace(P)) === ApproxFunBase.blocklengths(domainspace(P.op)) &&
                    ApproxFunBase.blocklengths(rangespace(P)) === ApproxFunBase.blocklengths(rangespace(P.op))
                ApproxFunBase.PseudoBlockMatrix(view(parent(S).op,S.indexes[1],S.indexes[2]))
            else
                ApproxFunBase.default_blockmatrix(S)
            end
        end

        function ApproxFunBase.BandedBlockBandedMatrix(S::ApproxFunBase.SubOperator{T,OP}) where {T,OP<:$Wrap}
            P = parent(S)
            if ApproxFunBase.blocklengths(domainspace(P)) === ApproxFunBase.blocklengths(domainspace(P.op)) &&
                    ApproxFunBase.blocklengths(rangespace(P)) === ApproxFunBase.blocklengths(rangespace(P.op))
                ApproxFunBase.BandedBlockBandedMatrix(view(parent(S).op,S.indexes[1],S.indexes[2]))
            else
                ApproxFunBase.default_BandedBlockBandedMatrix(S)
            end
        end

        ApproxFunBase.@wrapperstructure($Wrap) # structure is automatically inherited
    end

    esc(ret)
end

# use this for wrapper operators that have the same spaces but
# not necessarily the same entries or structure
#
macro wrapperspaces(Wrap)
    ret = quote  end

    for func in (:(ApproxFunBase.rangespace),:(ApproxFunBase.domain),
                 :(ApproxFunBase.domainspace),:(ApproxFunBase.isconstop))
        ret = quote
            $ret

            $func(D::$Wrap) = $func(D.op)
        end
    end

    esc(ret)
end


# use this for wrapper operators that have the same entries and same spaces
#
macro wrapper(Wrap)
    ret = quote
        ApproxFunBase.@wrappergetindex($Wrap)
        ApproxFunBase.@wrapperspaces($Wrap)

        ApproxFunBase.iswrapper(::$Wrap) = true
    end


    esc(ret)
end

## Standard Operators and linear algebra



include("ldiv.jl")

include("spacepromotion.jl")
include("banded/banded.jl")
include("general/general.jl")

include("functionals/functionals.jl")
include("almostbanded/almostbanded.jl")

include("systems.jl")

include("qr.jl")
include("nullspace.jl")




## Conversion



zero(::Type{Operator{T}}) where {T<:Number} = ZeroOperator(T)
zero(::Type{O}) where {O<:Operator} = ZeroOperator(eltype(O))


Operator(L::UniformScaling) = ConstantOperator(L, UnsetSpace())
Operator(L::UniformScaling, s::Space) = ConstantOperator(L, s)
Operator(L::UniformScaling{Bool}, s::Space) = L.λ ? IdentityOperator(s) : ZeroOperator(s)
Operator(L::UniformScaling, d::Domain) = Operator(L, Space(d))

Operator{T}(f::Fun) where {T} =
    norm(f.coefficients)==0 ? zero(Operator{T}) : convert(Operator{T}, Multiplication(f))

Operator(f::Fun) = norm(f.coefficients)==0 ? ZeroOperator() : Multiplication(f)

convert(::Type{O}, f::Fun) where O<:Operator = O(f)
Operator{T}(A::Operator) where T = convert(Operator{T}, A)


## Promotion





promote_rule(::Type{N},::Type{Operator}) where {N<:Number} = Operator{N}
promote_rule(::Type{UniformScaling{N}},::Type{Operator}) where {N<:Number} =
    Operator{N}
promote_rule(::Type{Fun{S,N,VN}},::Type{Operator}) where {S,N<:Number,VN} = Operator{N}
promote_rule(::Type{N},::Type{O}) where {N<:Number,O<:Operator} =
    Operator{promote_type(N,eltype(O))}  # float because numbers are promoted to Fun
promote_rule(::Type{UniformScaling{N}},::Type{O}) where {N<:Number,O<:Operator} =
    Operator{promote_type(N,eltype(O))}
promote_rule(::Type{Fun{S,N,VN}},::Type{O}) where {S,N<:Number,O<:Operator,VN} =
    Operator{promote_type(N,eltype(O))}

promote_rule(::Type{BO1},::Type{BO2}) where {BO1<:Operator,BO2<:Operator} =
    Operator{promote_type(eltype(BO1),eltype(BO2))}




## Wrapper

#TODO: Should cases that modify be included?
const WrapperOperator = Union{SpaceOperator,MultiplicationWrapper,DerivativeWrapper,IntegralWrapper,
                                    ConversionWrapper,ConstantTimesOperator,TransposeOperator}





# The following support converting an Operator to a Matrix or BandedMatrix

## BLAS and matrix routines
# We assume that copy may be overriden

BLAS.axpy!(a, X::Operator, Y::AbstractMatrix) = (Y .= a .* AbstractMatrix(X) .+ Y)
copyto!(dest::AbstractMatrix, src::Operator) = copyto!(dest, AbstractMatrix(src))

# this is for operators that implement copy via axpy!

BandedMatrix(::Type{Zeros}, V::Operator) = BandedMatrix(Zeros{eltype(V)}(size(V)), bandwidths(V))
Matrix(::Type{Zeros}, V::Operator) = Matrix(Zeros{eltype(V)}(size(V)))
BandedBlockBandedMatrix(::Type{Zeros}, V::Operator) =
    BandedBlockBandedMatrix(Zeros{eltype(V)}(size(V)),
                            blocklengths(rangespace(V)), blocklengths(domainspace(V)),
                            blockbandwidths(V), subblockbandwidths(V))
BlockBandedMatrix(::Type{Zeros}, V::Operator) =
    BlockBandedMatrix(Zeros{eltype(V)}(size(V)),
                      AbstractVector{Int}(blocklengths(rangespace(V))),
                       AbstractVector{Int}(blocklengths(domainspace(V))),
                      blockbandwidths(V))
RaggedMatrix(::Type{Zeros}, V::Operator) =
    RaggedMatrix(Zeros{eltype(V)}(size(V)),
                 Int[max(0,colstop(V,j)) for j=1:size(V,2)])


convert_axpy!(::Type{MT}, S::Operator) where {MT <: AbstractMatrix} =
        BLAS.axpy!(one(eltype(S)), S, MT(Zeros, S))



BandedMatrix(S::Operator) = default_BandedMatrix(S)

function BlockBandedMatrix(S::Operator)
    if isbandedblockbanded(S)
        BlockBandedMatrix(BandedBlockBandedMatrix(S))
    else
        default_BlockBandedMatrix(S)
    end
end

function default_BlockMatrix(S::Operator)
    ret = PseudoBlockArray(zeros(size(S)),
                        AbstractVector{Int}(blocklengths(rangespace(S))),
                        AbstractVector{Int}(blocklengths(domainspace(S))))
    ret .= S
    ret
end

function PseudoBlockMatrix(S::Operator)
    if isbandedblockbanded(S)
        PseudoBlockMatrix(BandedBlockBandedMatrix(S))
    elseif isblockbanded(S)
        PseudoBlockMatrix(BlockBandedMatrix(S))
    else
        default_BlockMatrix(S)
    end
end


# TODO: Unify with SubOperator
for TYP in (:RaggedMatrix, :Matrix)
    def_TYP = Symbol(string("default_", TYP))
    @eval function $TYP(S::Operator)
        if isinf(size(S,1)) || isinf(size(S,2))
            error("Cannot convert $S to a ", $TYP)
        end

        if isbanded(S)
            $TYP(BandedMatrix(S))
        else
            $def_TYP(S)
        end
    end
end

function Vector(S::Operator)
    if size(S,2) ≠ 1  || isinf(size(S,1))
        error("Cannot convert $S to a AbstractVector")
    end

    eltype(S)[S[k] for k=1:size(S,1)]
end

convert(::Type{AA}, B::Operator) where AA<:AbstractArray = AA(B)


# TODO: template out fully
arraytype(::Operator) = Matrix
function arraytype(V::SubOperator{T,B,Tuple{KR,JR}}) where {T, B, KR <: Union{BlockRange, Block}, JR <: Union{BlockRange, Block}}
    P = parent(V)
    isbandedblockbanded(P) && return BandedBlockBandedMatrix
    isblockbanded(P) && return BlockBandedMatrix
    return PseudoBlockMatrix
end

function arraytype(V::SubOperator{T,B,Tuple{KR,JR}}) where {T, B, KR <: Block, JR <: Block}
    P = parent(V)
    isbandedblockbanded(V) && return BandedMatrix
    return Matrix
end


function arraytype(V::SubOperator)
    P = parent(V)
    isbanded(P) && return BandedMatrix
    # isbandedblockbanded(P) && return BandedBlockBandedMatrix
    isinf(size(P,1)) && israggedbelow(P) && return RaggedMatrix
    return Matrix
end

AbstractMatrix(V::Operator) = arraytype(V)(V)
AbstractVector(S::Operator) = Vector(S)




# default copy is to loop through
# override this for most operators.
function default_BandedMatrix(S::Operator)
    Y=BandedMatrix{eltype(S)}(undef, size(S), bandwidths(S))

    for j=1:size(S,2),k=colrange(Y,j)
        @inbounds inbands_setindex!(Y,S[k,j],k,j)
    end

    Y
end


# default copy is to loop through
# override this for most operators.
function default_RaggedMatrix(S::Operator)
    data=Array{eltype(S)}(undef, 0)
    cols=Array{Int}(undef, size(S,2)+1)
    cols[1]=1
    for j=1:size(S,2)
        cs=colstop(S,j)
        K=cols[j]-1
        cols[j+1]=cs+cols[j]
        resize!(data,cols[j+1]-1)

        for k=1:cs
            data[K+k]=S[k,j]
        end
    end

    RaggedMatrix(data,cols,size(S,1))
end

function default_Matrix(S::Operator)
    n, m = size(S)
    if isinf(n) || isinf(m)
        error("Cannot convert $S to a Matrix")
    end

    eltype(S)[S[k,j] for k=1:n, j=1:m]
end




# The diagonal of the operator may not be the diagonal of the sub
# banded matrix, so the following calculates the row of the
# Banded matrix corresponding to the diagonal of the original operator


diagindshift(S,kr,jr) = first(kr)-first(jr)
diagindshift(S::SubOperator) = diagindshift(S,parentindices(S)[1],parentindices(S)[2])


#TODO: Remove
diagindrow(S,kr,jr) = bandwidth(S,2)+first(jr)-first(kr)+1
diagindrow(S::SubOperator) = diagindrow(S,parentindices(S)[1],parentindices(S)[2])
