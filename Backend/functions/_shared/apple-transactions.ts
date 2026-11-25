import { Environment, SignedDataVerifier } from "npm:@apple/app-store-server-library@3.1.0";
import { Buffer } from "node:buffer";
import { fail, jws, obj } from "./district-api.ts";

const bundleID = "com.sese.citycommunit";
// Apple PKI, Apple Root CA - G3. SHA-256 63343abfb89a6a03ebb57e9b3f5fa7be7c4f5c756f3017b3a8c488c3653e9179.
const appleRoot = Buffer.from("MIICQzCCAcmgAwIBAgIILcX8iNLFS5UwCgYIKoZIzj0EAwMwZzEbMBkGA1UEAwwSQXBwbGUgUm9vdCBDQSAtIEczMSYwJAYDVQQLDB1BcHBsZSBDZXJ0aWZpY2F0aW9uIEF1dGhvcml0eTETMBEGA1UECgwKQXBwbGUgSW5jLjELMAkGA1UEBhMCVVMwHhcNMTQwNDMwMTgxOTA2WhcNMzkwNDMwMTgxOTA2WjBnMRswGQYDVQQDDBJBcHBsZSBSb290IENBIC0gRzMxJjAkBgNVBAsMHUFwcGxlIENlcnRpZmljYXRpb24gQXV0aG9yaXR5MRMwEQYDVQQKDApBcHBsZSBJbmMuMQswCQYDVQQGEwJVUzB2MBAGByqGSM49AgEGBSuBBAAiA2IABJjpLz1AcqTtkyJygRMc3RCV8cWjTnHcFBbZDuWmBSp3ZHtfTjjTuxxEtX/1H7YyYl3J6YRbTzBPEVoA/VhYDKX1DyxNB0cTddqXl5dvMVztK517IDvYuVTZXpmkOlEKMaNCMEAwHQYDVR0OBBYEFLuw3qFYM4iapIqZ3r6966/ayySrMA8GA1UdEwEB/wQFMAMBAf8wDgYDVR0PAQH/BAQDAgEGMAoGCCqGSM49BAMDA2gAMGUCMQCD6cHEFl4aXTQY2e3v9GwOAEZLuN+yRhHFD/3meoyhpmvOwgPUnPWTxnS4at+qIxUCMG1mihDK1A3UT82NQz60imOlM27jbdoXt2QfyFMm+YhidDkLF1vLUagM6BgD56KyKA==", "base64");

export async function productionVerifier(signedAppTransaction: unknown): Promise<SignedDataVerifier> {
  const pin = Deno.env.get("SESE_APP_APPLE_ID");
  let appleID: number;
  let appJWS: string | undefined;
  if (signedAppTransaction !== undefined) appJWS = jws(signedAppTransaction);
  if (pin !== undefined) {
    if (!/^[1-9]\d{0,15}$/.test(pin)) fail("service_unavailable");
    appleID = Number(pin);
  } else if (appJWS) {
    try {
      // This untrusted value selects a verifier. The entire JWS must pass the
      // official verifier for our pinned bundle/environment before it is used.
      const payload = obj(JSON.parse(Buffer.from(appJWS.split(".")[1], "base64url").toString("utf8")));
      if (typeof payload.appAppleId !== "number") fail();
      appleID = payload.appAppleId;
    } catch { fail("transaction_review"); }
  } else fail("transaction_review");
  if (!Number.isSafeInteger(appleID) || appleID <= 0) fail("transaction_review");
  const verifier = new SignedDataVerifier([appleRoot], true, Environment.PRODUCTION, bundleID, appleID);
  if (appJWS) {
    try {
      const app = await verifier.verifyAndDecodeAppTransaction(appJWS);
      if (app.appAppleId !== appleID || app.bundleId !== bundleID || app.receiptType !== Environment.PRODUCTION) fail();
    } catch { fail("transaction_review"); }
  }
  return verifier;
}

export async function verifyPurchase(
  verifier: SignedDataVerifier, signedTransaction: string, transaction: string, product: string, accountToken: string,
) {
  try {
    const evidence = await verifier.verifyAndDecodeTransaction(signedTransaction);
    if (evidence.bundleId !== bundleID || evidence.environment !== Environment.PRODUCTION ||
        evidence.transactionId !== transaction || evidence.productId !== product || evidence.type !== "Consumable" ||
        evidence.inAppOwnershipType !== "PURCHASED" || evidence.appAccountToken?.toLowerCase() !== accountToken ||
        evidence.revocationDate != null || evidence.revocationReason != null ||
        !Number.isSafeInteger(evidence.quantity) || evidence.quantity! < 1 || evidence.quantity! > 10 ||
        typeof evidence.purchaseDate !== "number" || evidence.purchaseDate <= 0 ||
        evidence.purchaseDate > Date.now() + 60000) fail();
    return { quantity: evidence.quantity!, purchaseDate: evidence.purchaseDate };
  } catch { fail("transaction_review"); }
}
