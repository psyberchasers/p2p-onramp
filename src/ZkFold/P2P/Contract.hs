{-# LANGUAGE UndecidableInstances #-}

module ZkFold.P2P.Contract where

import           Data.Maybe                           (fromJust)
import           GHC.Natural                          (Natural)
import           Prelude                              hiding (Bool, Eq ((==)),
                                                       any, elem, length,
                                                       splitAt, truncate, (&&),
                                                       (*), (+), (||))

import qualified Prelude                              as Haskell

import           ZkFold.Base.Algebra.Basic.Class      (AdditiveSemigroup (..),
                                                       MultiplicativeSemigroup (..),
                                                       fromConstant)
import           ZkFold.Symbolic.Algorithms.Hash.SHA2 (SHA2, sha2)
import           ZkFold.Symbolic.Cardano.Types        (Address (..), Input (..),
                                                       Output (..),
                                                       Transaction (..),
                                                       txInputs, txOutputs,
                                                       txoDatumHash)
import           ZkFold.Symbolic.Compiler             (SymbolicData)
import           ZkFold.Symbolic.Data.Bool            (Bool (..), BoolType (..),
                                                       any)
import           ZkFold.Symbolic.Data.ByteString      (ByteString (..),
                                                       Extend (..),
                                                       ShiftBits (..),
                                                       Truncate (..))
import           ZkFold.Symbolic.Data.Combinators     (Iso (..))
import           ZkFold.Symbolic.Data.Conditional     (Conditional (..))
import           ZkFold.Symbolic.Data.Eq              (Eq (..))
import           ZkFold.Symbolic.Data.UInt            (UInt (..))
import           ZkFold.Symbolic.Types                (Symbolic)

-- Should include part of PAN, account number holder, probably with PCI DSS masking
-- Can be finished when arithmetizable ByteStrings be ready
newtype FiatAccount a = FiatAccount a
    deriving Haskell.Eq

deriving instance
    SymbolicData i a => SymbolicData i (FiatAccount a)

newtype ISO427 a = ISO427 (a, (a, a))
    deriving Haskell.Eq

deriving instance
    SymbolicData i a
    => SymbolicData i (ISO427 a)

newtype Offer a = Offer
    (FiatAccount a, (UInt 64 a, ISO427 a))
    deriving Haskell.Eq

deriving instance
    ( SymbolicData i (UInt 64 a)
    , SymbolicData i a
    ) => SymbolicData i (Offer a)

newtype FiatTransfer a = FiatTransfer
    (FiatAccount a, Offer a)
    deriving Haskell.Eq

deriving instance
    ( SymbolicData i (FiatAccount a)
    , SymbolicData i (Offer a)
    ) => SymbolicData i (FiatTransfer a)

newtype MatchedOffer a = MatchedOffer
    (Address a, FiatTransfer a, (UInt 256 a, UInt 256 a))
    deriving Haskell.Eq

deriving instance
    ( SymbolicData i (UInt 64 a)
    , SymbolicData i (UInt 256 a)
    , SymbolicData i (Address a)
    , SymbolicData i a
    ) => SymbolicData i (MatchedOffer a)

hashMatchedOffer :: MatchedOffer a -> ByteString 256 a
hashMatchedOffer = undefined

-- | TODO: A temporary solution while we don't have a proper serialisation for the types above.
--
serialiseTransfer :: forall a. FiatTransfer a -> ByteString 1524 a
serialiseTransfer (FiatTransfer (FiatAccount r0, Offer (FiatAccount r1, (UInt rs r2, ISO427 (r3, (r4, r5)))))) = ByteString r0 (r1 : rs <> [r2, r3, r4, r5])


-- | An EdDSA signature on a message M by public key A is the pair (R, S), encoded in 2b bits,
-- of a curve point R ∈  E( Fq ) and an integer 0 < S < ℓ
verifyFiatTransferSignature
    :: forall a
    .  Symbolic a
    => Haskell.Eq a
    => Iso (UInt 256 a) (ByteString 256 a)
    => Extend (ByteString 1524 a) (ByteString 2036 a)
    => Extend (ByteString 256 a) (ByteString 2036 a)
    => BoolType (ByteString 2036 a)
    => ShiftBits (ByteString 2036 a)
    => AdditiveSemigroup (UInt 256 a)
    => MultiplicativeSemigroup (UInt 256 a)
    => Truncate (ByteString 512 a) (ByteString 256 a)
    => SHA2 "SHA512" a 2036
    => ByteString 256 a
    -> FiatTransfer a
    -> (UInt 256 a, UInt 256 a)
    -> Bool a
verifyFiatTransferSignature pubkey message (r, s) = (s * b) == (r + hInt * from pubkey)
    where
        fullMsg :: ByteString 2036 a
        fullMsg = (extend (from r :: ByteString 256 a) `shiftBitsL` 1780) || (extend pubkey `shiftBitsL` 1524) || extend messageBits

        h :: ByteString 512 a
        h = sha2 @"SHA512" fullMsg

        hInt :: UInt 256 a
        hInt = from $ (truncate h :: ByteString 256 a)

        b :: UInt 256 a
        b = fromConstant (15112221349535400772501151409588531511454012693041857206046113283949847762202 :: Natural)

        -- TODO: 1524 == 6 * 254 is the number of bits stored in 6 field elements required to describe FiatTransfer.
        -- We need to make this calculation automatic, but adding a type family @TypeSize a x@ to @Arithmetizable a@ requires too many changes in zkfold-base
        -- and breaks automatic deriving of @instance Arithmetizable a@
        --
        messageBits :: ByteString 1524 a
        messageBits = serialiseTransfer message

p2pMatchedOrderContract
    :: forall inputs rinputs outputs tokens a
    .  Symbolic a
    => Haskell.Eq a
    => Eq (Bool a) (Output () tokens a)
    => Eq (Bool a) (ByteString 256 a)
    => SHA2 "SHA512" a 2036
    => Iso (UInt 256 a) (ByteString 256 a)
    => Extend (ByteString 1524 a) (ByteString 2036 a)
    => Extend (ByteString 256 a) (ByteString 2036 a)
    => BoolType (ByteString 2036 a)
    => ShiftBits (ByteString 2036 a)
    => AdditiveSemigroup (UInt 256 a)
    => MultiplicativeSemigroup (UInt 256 a)
    => Truncate (ByteString 512 a) (ByteString 256 a)
    => Conditional (Bool a) (Maybe (Output () tokens a))
    => ByteString 256 a
    -> Transaction inputs rinputs  outputs tokens () a
    -> MatchedOffer a
    -> Bool a
p2pMatchedOrderContract vk tx mo@(MatchedOffer (addr, transfer, signature)) =
    let h                  = hashMatchedOffer mo
        f = (\o acc -> bool @(Bool a) acc (Just o) (txoDatumHash o == h))
        -- TODO: Simplify this using symbolic `find`.
        v = (\(Output (_, (v', _))) -> v') $ fromJust $ foldr f Nothing $
            fmap (\(Input (_, o)) -> o) $ txInputs tx
        -- TODO: Instead of `zero`, it should be the hash of `()`.
        txo                = Output (addr, (v, fromConstant (0 :: Natural) :: ByteString 256 a)) :: Output () tokens a
    in any (\o -> txo == o) (txOutputs tx) && verifyFiatTransferSignature vk transfer signature
