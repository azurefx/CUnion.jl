using Test
using CUnion

@testset "CUnion tests" begin
    @union struct U
        x::UInt16
        y::UInt32
        struct z
            a::UInt8
            b::UInt8
            c::UInt16
        end
    end
    u = U(0xabcd0123)
    @test u.x === 0x0123
    @test u.y === 0xabcd0123
    @test u.z.a === 0x23
    @test u.z.b === 0x01
    @test u.z.c === 0xabcd
    @test isprimitivetype(U)
    @test reinterpret(UInt32, u) === 0xabcd0123
    @test U(Dict(unionfields(U))[:z](0x23, 0x01, 0xabcd)) === u
end #testset
