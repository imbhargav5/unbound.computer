import { cache, Suspense } from "react";
import { T } from "@/components/type-system";
import { getRoadmap } from "@/data/anon/marketing-roadmap";
import { FeedbackPageHeading } from "../feedback/feedback-page-heading";
import { Roadmap } from "./roadmap";

const cachedGetRoadmap = cache(getRoadmap);

async function RoadmapContent() {
  const roadmapData = await cachedGetRoadmap();
  return (
    <div className="max-w-4xl space-y-6 py-6">
      <FeedbackPageHeading
        subTitle="This is where you see where the application is going"
        title="Roadmap"
        titleClassName="text-2xl font-semibold tracking-normal"
      />

      <Roadmap roadmapData={roadmapData} />
    </div>
  );
}

export default async function Page() {
  return (
    <Suspense fallback={<T.Subtle>Loading roadmap...</T.Subtle>}>
      <RoadmapContent />
    </Suspense>
  );
}
