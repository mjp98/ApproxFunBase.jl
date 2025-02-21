function CachedOperator(::Type{BandedMatrix},op::Operator;padding::Bool=false)
    l,u=bandwidths(op)
    padding && (u+=l)
    data = BandedMatrix{eltype(op)}(undef, (0,0), (l,u))
    CachedOperator(op,data,size(data),domainspace(op),rangespace(op),(-l,u),padding)
end



## Grow cached operator

function resizedata!(B::CachedOperator{T,<:BandedMatrix{T}},n::Integer,m_in::Integer) where T<:Number
    m = max(m_in,n+B.data.u)
    N,M = size(B)
    n = min(n, N)

    if n > B.datasize[1]
        pad!(B.data,min(N,2n),m)

        kr=B.datasize[1]+1:n
        jr=max(B.datasize[1]+1-B.data.l,1):min(n+B.data.u,M)
        BLAS.axpy!(1.0,view(B.op,kr,jr),view(B.data,kr,jr))

        B.datasize = (n,m)
    end

    B
end


resizedata!(B::CachedOperator{T,<:BandedMatrix{T}},n::Integer,::Colon) where T<:Number =
    resizedata!(B, n, n+B.data.u)

## Grow QR

function QROperator(R::CachedOperator{T,<:BandedMatrix{T}}) where T
    M = R.data.l+1   # number of diag+subdiagonal bands
    H = Array{T}(undef,M,100)
    QROperator(R,H,0)
end


function resizedata!(QR::QROperator{<:CachedOperator{T,<:BandedMatrix{T},
                                                  MM,DS,RS,BI}},
         ::Colon,col) where {T,MM,DS,RS,BI}
    if col ≤ QR.ncols
        return QR
    end

    MO=QR.R_cache
    W=QR.H

    R=MO.data
    M=R.l+1   # number of diag+subdiagonal bands

    if col+M-1 ≥ MO.datasize[1]
        resizedata!(MO,(col+M-1)+100,:)  # double the last rows
    end

    if col > size(W,2)
        W=QR.H=unsafe_resize!(W,:,2col)
    end

    for k=QR.ncols+1:col
        W[:,k] = view(R.data,R.u+1:R.u+R.l+1,k) # diagonal and below
        wp=view(W,:,k)
        W[1,k]+= flipsign(norm(wp),W[1,k])
        normalize!(wp)

        # scale banded entries
        for j=k:k+R.u
            dind=R.u+1+k-j
            v=view(R.data,dind:dind+M-1,j)
            dt=dot(wp,v)
            LinearAlgebra.axpy!(-2*dt,wp,v)
        end

        # scale banded/filled entries
        for j=k+R.u+1:k+R.u+M-1
            p=j-k-R.u
            v=view(R.data,1:M-p,j)  # shift down each time
            wp2=view(wp,p+1:M)
            dt=dot(wp2,v)
            LinearAlgebra.axpy!(-2*dt,wp2,v)
        end
    end
    QR.ncols=col
    QR
end


# BLAS versions, requires BlasFloat



function resizedata!(QR::QROperator{<:CachedOperator{T,<:BandedMatrix{T},
                                       MM,DS,RS,BI}},
                     ::Colon,col) where {T<:BlasFloat,MM,DS,RS,BI}
    if col ≤ QR.ncols
        return QR
    end

    col = min(col, size(QR,2))

    MO=QR.R_cache
    W=QR.H

    R=MO.data
    M=R.l+1   # number of diag+subdiagonal bands

    if col+M-1 ≥ MO.datasize[1]
        resizedata!(MO,(col+M-1)+100,:)  # double the last rows
    end

    if col > size(W,2)
        W=QR.H=unsafe_resize!(W,:,2col)
    end

    m,n=size(R)
    w=pointer(W)
    r=pointer(R.data)
    sz=sizeof(T)
    st=stride(R.data,2)
    stw=stride(W,2)

    for k=QR.ncols+1:col
        v=r+sz*(R.u + (k-1)*st)    # diagonal entry
        wp=w+stw*sz*(k-1)          # k-th column of W
        BLAS.blascopy!(M,v,1,wp,1)
        W[1,k]+= flipsign(BLAS.nrm2(M,wp,1),W[1,k])
        normalize!(M,wp)

        for j=k:k+R.u
            v=r+sz*(R.u + (k-1)*st + (j-k)*(st-1))
            dt = dot(M,wp,1,v,1)
            BLAS.axpy!(M,-2*dt,wp,1,v,1)
        end

        for j=k+R.u+1:k+R.u+M-1
            p=j-k-R.u
            v=r+sz*((j-1)*st)  # shift down each time
            dt = dot(M-p,wp+p*sz,1,v,1)
            BLAS.axpy!(M-p,-2*dt,wp+p*sz,1,v,1)
        end
    end
    QR.ncols=col
    QR
end


## back substitution
# loop to avoid ambiguity with AbstractTRiangular
for ArrTyp in (:AbstractVector, :AbstractMatrix, :StridedVector)
    @eval function ldiv!(U::UpperTriangular{T, <:SubArray{T, 2, <:BandedMatrix{T}, Tuple{UnitRange{Int}, UnitRange{Int}}, false}},
                             u::$ArrTyp{T}) where T
        n = size(u,1)
        n == size(U,1) || throw(DimensionMismatch())

        V = parent(U)
        @assert first(parentindices(V)[1]) == 1
        @assert first(parentindices(V)[2]) == 1

        A = parent(V)

        b=bandwidth(A,2)

        for c=1:size(u,2)
            for k=n:-1:1
                @simd for j=k+1:min(n,k+b)
                    @inbounds u[k,c] = muladd(-A.data[k-j+A.u+1,j],u[j,c],u[k,c])
                end

                @inbounds u[k,c] /= A.data[A.u+1,k]
            end
        end
        u
    end
end
