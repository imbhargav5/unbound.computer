import { PageHeading } from "@/components/PageHeading";
import { getRoadmap } from "@/data/admin/marketing-roadmap";
import { serverGetUserType } from "@/utils/server/serverGetUserType";
import { userRoles } from "@/utils/userTypes";
import { AppAdminRoadmap } from "./AppAdminRoadmap";
import { Roadmap } from "./Roadmap";

export default async function Page() {
  const roadmapData = await getRoadmap();
  const userRoleType = await serverGetUserType();
  return (
    <div className="space-y-10 max-w-[1296px]">
      <PageHeading
        title="Roadmap"
        titleClassName="text-2xl font-semibold tracking-normal"
        subTitle="This is where you see where the application is going"
      />

      {userRoleType === userRoles.ADMIN ? (
        <AppAdminRoadmap roadmapData={roadmapData} />
      ) : (
        <Roadmap roadmapData={roadmapData} />
      )}
    </div>
  );
}
