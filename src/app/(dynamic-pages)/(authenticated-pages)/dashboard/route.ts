import { getInitialOrganizationToRedirectTo } from '@/data/user/organizations';
import { toSiteURL } from '@/utils/helpers';
import { NextRequest, NextResponse } from 'next/server';

export const dynamic = 'force-dynamic';

export async function GET(req: NextRequest) {
  try {
    const initialOrganization = await getInitialOrganizationToRedirectTo();
    if (initialOrganization.status === 'error') {
      return NextResponse.redirect(toSiteURL('/500'));
    }
    return NextResponse.redirect(new URL(`/${initialOrganization.data}`, req.url));
  } catch (error) {
    console.error('Failed to load dashboard:', error);
    // Redirect to an error page or show an error message
    return NextResponse.redirect(toSiteURL('/500'));
  }
}
