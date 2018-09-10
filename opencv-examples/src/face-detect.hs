{-# language DataKinds #-}
{-# language FlexibleInstances #-}
{-# language ScopedTypeVariables #-}
{-# language TemplateHaskell #-}
{-# language TupleSections #-}
{-# language ViewPatterns #-}
{-# language FlexibleContexts #-}

import qualified OpenCV as CV
import qualified OpenCV.Internal.Core.Types.Mat as CV
import OpenCV.VideoIO.Types
import GHC.Word (Word8)
import OpenCV.Example
import qualified Data.Vector as V
import OpenCV.TypeLevel
import Linear.V2 ( V2(..) )
import Linear.V4 ( V4(..)  )
import Data.Int
import Data.Foldable
import GHC.TypeLits ()
import Data.Proxy
import Control.Monad
import Control.Monad.Trans.Class


green,blue ,white:: CV.Scalar
green  = CV.toScalar (V4   0 255   0 255 :: V4 Double)
blue   = CV.toScalar (V4 255   0   0 255 :: V4 Double)
white  = CV.toScalar (V4 255 255 255 255 :: V4 Double)

main :: IO ()
main = do
    cap <- createCaptureArg
    Just ccFrontal <- $(withEmbeddedFile "data/haarcascade_frontalface_default.xml") CV.newCascadeClassifier
    Just ccEyes    <- $(withEmbeddedFile "data/haarcascade_eye.xml") CV.newCascadeClassifier
    w <- CV.videoCaptureGetI cap VideoCapPropFrameWidth
    h <- CV.videoCaptureGetI cap VideoCapPropFrameHeight
    CV.withWindow "video" $ loop cap (ccFrontal, ccEyes, w, h)
  where
    ccDetectMultiscale cc = CV.cascadeClassifierDetectMultiScale cc Nothing Nothing minSize maxSize

    minSize = Nothing :: Maybe (V2 Int32)
    maxSize = Nothing :: Maybe (V2 Int32)
    addCorner (CV.fromRect -> CV.HRect (V2 tx ty) _) (CV.fromRect -> CV.HRect (V2 ex ey) b) =
         CV.toRect (CV.HRect (V2 (tx + ex) (ty + ey)) b)

    loop cap param@(ccFrontal, ccEyes, w, h) window = do
      _ok <- CV.videoCaptureGrab cap
      mbImg <- CV.videoCaptureRetrieve cap
      case mbImg of
        Just img -> do
          -- Assert that the retrieved frame is 2-dimensional.
          img' :: CV.Mat ('S ['D, 'D]) ('S 3) ('S Word8)
               <- CV.exceptErrorIO $ CV.coerceMat img
          imgGray <- CV.exceptErrorIO $ CV.cvtColor CV.bgr CV.gray img'
          faces <- CV.exceptErrorIO $ ccDetectMultiscale ccFrontal imgGray
          eyedFaces <-
              fmap (V.concat . V.toList) $ CV.exceptErrorIO $
                mapM
                  (\faceRect -> do
                     faceImg <- CV.matSubRect imgGray faceRect
                     eyeRects <- ccDetectMultiscale ccEyes faceImg
                     pure $ V.map (addCorner faceRect) eyeRects
                  )
                  faces

          let box = CV.exceptError $
                CV.withMatM (h ::: w ::: Z) (Proxy :: Proxy 3) (Proxy :: Proxy Word8) white $ \imgM -> do
                  void $ CV.matCopyToM imgM (V2 0 0) (CV.unsafeCoerceMat img) Nothing
                  for_ eyedFaces $ \eyeRect  -> lift $ CV.rectangle imgM eyeRect green 2 CV.LineType_8 0
                  for_ faces $ \faceRect -> lift $ CV.rectangle imgM faceRect blue 2 CV.LineType_8 0
          CV.imshow window ( CV.unsafeCoerceMat box )

          key <- CV.waitKey 20
          -- Loop unless the escape key is pressed.
          unless (key == 27) $ loop cap param window

        -- Out of frames, stop looping.
        Nothing -> pure ()
