import { Outbound } from "../config/Config";
export interface IShareLinkImporterResult {
    name: string;
    outbound: Outbound;
}

export interface IShareLinkImporter {
    readonly name: string;
    matcher(link: string): boolean;
    decode(link: string): IShareLinkImporterResult | undefined;
}
