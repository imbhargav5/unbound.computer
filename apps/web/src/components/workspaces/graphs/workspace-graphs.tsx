"use client";
import { motion } from "motion/react";
import { BarChartActive } from "./bar-chart-active";
import { BarChartInteractive } from "./bar-chart-interactive";
import { LineChartInteractive } from "./line-chart-interactive";
import { RadarChartGridCircleFilled } from "./radar-chart-grid-circle-filled";
import { RadialChartGrid } from "./radial-chart-grid";

const containerVariants = {
  hidden: { opacity: 0 },
  visible: {
    opacity: 1,
    transition: {
      staggerChildren: 0.1,
    },
  },
};

const itemVariants = {
  hidden: { y: 20, opacity: 0 },
  visible: {
    y: 0,
    opacity: 1,
    transition: {
      type: "spring" as const,
      stiffness: 100,
    },
  },
};

export function WorkspaceGraphs() {
  return (
    <motion.div
      animate="visible"
      className="flex flex-col gap-6"
      initial="hidden"
      variants={containerVariants}
    >
      <motion.div variants={itemVariants}>
        <BarChartInteractive />
      </motion.div>
      <motion.div variants={itemVariants}>
        <LineChartInteractive />
      </motion.div>
      <motion.div
        className="grid w-full grid-flow-row auto-rows-max grid-cols-1 gap-6 md:grid-cols-2 lg:grid-cols-3"
        variants={containerVariants}
      >
        <motion.div variants={itemVariants}>
          <BarChartActive />
        </motion.div>
        <motion.div variants={itemVariants}>
          <RadialChartGrid />
        </motion.div>
        <motion.div variants={itemVariants}>
          <RadarChartGridCircleFilled />
        </motion.div>
      </motion.div>
    </motion.div>
  );
}
