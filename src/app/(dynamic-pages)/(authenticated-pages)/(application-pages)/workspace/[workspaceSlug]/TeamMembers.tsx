
import { Avatar, AvatarFallback, AvatarImage } from "@/components/ui/avatar";
import { Badge } from "@/components/ui/badge";
import { getAllOrganizationsForUser } from "@/data/user/organizations";
import type { Tables } from "@/lib/database.types";
import { serverGetLoggedInUser } from "@/utils/server/serverGetLoggedInUser";

export type OrganizationDetails = {
  created_at: string;
  id: string;
  title: string;
  organization_members: {
    id: number;
    member_id: string;
    member_role: "owner" | "admin" | "member" | "readonly";
    user_profiles: Tables<"user_profiles"> | null;
  }[]
}

export const TeamMembers = async () => {
  const user = await serverGetLoggedInUser()
  const organizations = await getAllOrganizationsForUser(user.id)
  const organizationsMembers = organizations.flatMap(organization => organization.organization_members)
  return (
    <div className='flex flex-col overflow-y-auto gap-2'>
      {organizationsMembers.map((member) => (
        <div key={member.id} className="flex items-center justify-between px-8 ">
          <div className='flex items-center gap-4'>
            <Avatar>
              <AvatarImage src={member.user_profiles?.avatar_url || ''} />
              <AvatarFallback className="bg-secondary">
                <span>{member.user_profiles?.full_name?.charAt(0) || ''}</span>
              </AvatarFallback>
            </Avatar>
            <span>{member.user_profiles?.full_name}</span>
          </div>
          <div>
            <Badge>
              {member.member_role}
            </Badge>
          </div>
        </div>
      ))}
    </div>
  )
};
