'use client'

import { motion as framerMotion, HTMLMotionProps } from 'framer-motion';

const MotionDiv = (props: HTMLMotionProps<"div">) => {
  return <framerMotion.div {...props} />;
}

export { MotionDiv };

