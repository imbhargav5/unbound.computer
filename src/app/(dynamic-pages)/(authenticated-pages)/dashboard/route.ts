import { getMaybeDefaultWorkspace } from '@/data/user/workspaces';
import { toSiteURL } from '@/utils/helpers';
import { NextRequest, NextResponse } from 'next/server';

export const dynamic = 'force-dynamic';

export async function GET(req: NextRequest) {
  try {
    const initialWorkspace = await getMaybeDefaultWorkspace();
    if (!initialWorkspace) {
      return NextResponse.redirect(toSiteURL('/500'));
    }
    if (initialWorkspace.workspaceMembershipType === 'solo') {
      return NextResponse.redirect(new URL(`/${initialWorkspace.workspace.slug}`, req.url));
    }
    return NextResponse.redirect(new URL(`/${initialWorkspace.workspace.slug}`, req.url));
  } catch (error) {
    console.error('Failed to load dashboard:', error);
    // Redirect to an error page or show an error message
    return NextResponse.redirect(toSiteURL('/500'));
  }
}
