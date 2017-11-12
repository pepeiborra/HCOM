-- This file is licensed under the New BSD License
module SafeArraySpec (safeArraySpec) where

import Control.Monad
import qualified Data.ByteString.Char8 as B
import Data.Char
import Data.Time
import Foreign
import System.Win32.HCOM

import Test.Hspec
import ISATest

-- {50C1BE3B-1298-4D57-A781-2212EBFFD961}
clsid_MySATest = GUID 0x50C1BE3B 0x1298 0x4D57 0xA781 0x22 0x12 0xEB 0xFF 0xD9 0x61

clsid_Scripting_Dictionary = GUID 0xEE09B103 0x97E0 0x11CF 0x978F 0x00 0xA0 0x24 0x63 0xE0 0x6F

-- Test that passing the array to a COM function which'll then index
-- in is equivalent to looking it up ourselves.
testLookup ptr sa = do
  res <- ptr ~> isatest_4 sa
  let res' = sa ! [3, 4]
  when (res /= res') $
       error "Lookup mismatch!"

testLookups ptr = do
  testLookup ptr $ SafeArray [(2,4), (3, 4)] [1..6]
  testLookup ptr $ SafeArray [(1,4), (1, 4)] [1..16]
  testLookup ptr $ SafeArray [(0,3), (4, 5)] [1..8]
  testLookup ptr $ SafeArray [(1,4), (4, 5)] [1..8]
  testLookup ptr $ SafeArray [(1,4), (3, 4)] [1..8]
  testLookup ptr $ SafeArray [(1,4), (3, 4)] [1..8]

-- Compare the before and after SA from a call to isatest_2: The
-- indices and elements should be the same, except the second element,
-- which gets overwritten with 180.
compare2 sa sa' = boundsEqual && dataEqual where
    boundsEqual = saBounds sa == saBounds sa'
    data1 = saData sa
    data2 = saData sa'
    dataEqual = length data1 == length data2 &&
                and (zipWith3 f data1 data2 [1..])
    f x y i = if i == 2
              then y == 180
              else x == y

safeArraySpec = {- replicateM_ 10 $ -} beforeAll (coCreate clsid_MySATest) $ do
  -- isatest_[1..3] (used in these tests) test both different
  -- primitive types, and different parameter-passing mechanisms.
  it "testIn" $ \ptr ->
    -- We don't really test much for in parameters, I'm afraid. The COM
    -- server implementation should do the testing, really!
    ptr ~> isatest_1 (SafeArray [(1, 3)] [10, 20, 30]) `shouldReturn` ()
  it "testInOut" $ \ptr -> do
    let sa = SafeArray [(1, 3)] [100, 200, 300]
    sa' <- ptr ~> isatest_2 sa
    sa' `shouldSatisfy` compare2 sa
  it "testOut" $ \ptr -> do
    sa <- ptr ~> isatest_3
    let str = map (chr . fromIntegral) $ saData sa
    str `shouldBe` "foo!1"
  it "testBoundsPreservation" $ \ptr -> do
    let sa = SafeArray [(1, 3), (5,6)] [100, 200, 300, 1000, 2000, 3000]
    sa' <- ptr ~> isatest_2 sa
    sa' `shouldSatisfy` compare2 sa
  it "testBool" $ \ptr -> do
    let sa = fromList [True, False, True]
    sa' <- ptr ~> isatest_bool sa
    sa' `shouldBe` sa
  it "testBSTR" $ \ptr -> do
    let sa = fromList ["FOO", "BAR", "Bazzle", ""]
    sa' <- ptr ~> isatest_bstr sa
    sa' `shouldBe` sa
  it "testObj"  $ \ptr -> do
    tmpPtr1 <- coCreate clsid_Scripting_Dictionary
    tmpPtr2 <- snd <$> queryInterface ptr
    let sa = fromList [tmpPtr1, tmpPtr2, nullCOMPtr, tmpPtr1]
    sa' <- ptr ~> isatest_obj sa
    sa' `shouldBe` sa
  it "test Var"  $ \ptr -> do
    tmpPtr <- snd <$> queryInterface ptr
    let sa = fromList [vt (42 :: Int16),
                       vt True,
                       vt "Hello!",
                       vt (tmpPtr :: COMPtr IUnknown)]
    sa' <- ptr ~> isatest_var sa
    sa' `shouldBe` sa
  it "test SafeArray in variant" $ \ptr -> do
    let v = vt $ fromList $ fmap B.pack ["Foo", "Bar", "Barney"]
    v' <- ptr ~> isatest_v v
    v' `shouldBe` v
  it "test SafeArray in variant (2)" $ \ptr -> do
    tmpPtr <- snd <$> queryInterface ptr
    let v = vt $ fromList [vt "Foo",
                           vt False,
                           vt (tmpPtr :: COMPtr IDispatch),
                           vt (1234.567 :: Float),
                           vt (UTCTime (fromGregorian 1979 4 17) (6 * 60 * 60)),
                           VT_NULL,
                           vt (987.432 :: Double)]
    v' <- ptr ~> isatest_v v
    v' `shouldBe` v