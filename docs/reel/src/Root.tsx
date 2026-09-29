import React from "react";
import { Composition } from "remotion";
import { Reel, totalFrames, FPS } from "./Reel";

export const Root: React.FC = () => (
  <Composition id="Reel" component={Reel} durationInFrames={totalFrames} fps={FPS} width={1920} height={1080} />
);
