// User service — account-management endpoints backed by Cognito admin
// APIs. Sign-up/sign-in themselves happen directly against Cognito from
// the frontend (SRP / hosted UI) and never pass through this service —
// this only handles server-side admin operations on an existing account.
'use strict';

const express = require('express');
const {
  CognitoIdentityProviderClient,
  AdminGetUserCommand,
  AdminUpdateUserAttributesCommand,
  AdminDeleteUserCommand,
} = require('@aws-sdk/client-cognito-identity-provider');

const PORT = process.env.PORT || 8083;
const REGION = process.env.AWS_REGION || 'eu-west-2';
const USER_POOL_ID = process.env.COGNITO_USER_POOL_ID;

const cognito = new CognitoIdentityProviderClient({ region: REGION });

const app = express();
app.use(express.json());

app.get('/health', (_req, res) => res.status(200).json({ status: 'ok' }));

// :username is the Cognito "sub"/username, expected to be the caller's own
// identity as extracted from the verified JWT at the API Gateway layer.
app.get('/users/:username', async (req, res) => {
  try {
    const result = await cognito.send(
      new AdminGetUserCommand({ UserPoolId: USER_POOL_ID, Username: req.params.username })
    );
    res.json({
      username: result.Username,
      enabled: result.Enabled,
      status: result.UserStatus,
      attributes: Object.fromEntries(
        (result.UserAttributes || []).map((a) => [a.Name, a.Value])
      ),
    });
  } catch (err) {
    if (err.name === 'UserNotFoundException') {
      return res.status(404).json({ error: 'not found' });
    }
    console.error('get user failed', err);
    res.status(500).json({ error: 'failed to get user' });
  }
});

app.patch('/users/:username', async (req, res) => {
  const attributes = req.body?.attributes;
  if (!attributes || typeof attributes !== 'object') {
    return res.status(400).json({ error: 'attributes object is required' });
  }
  try {
    await cognito.send(
      new AdminUpdateUserAttributesCommand({
        UserPoolId: USER_POOL_ID,
        Username: req.params.username,
        UserAttributes: Object.entries(attributes).map(([Name, Value]) => ({ Name, Value })),
      })
    );
    res.status(204).end();
  } catch (err) {
    console.error('update user failed', err);
    res.status(500).json({ error: 'failed to update user' });
  }
});

app.delete('/users/:username', async (req, res) => {
  try {
    await cognito.send(
      new AdminDeleteUserCommand({ UserPoolId: USER_POOL_ID, Username: req.params.username })
    );
    res.status(204).end();
  } catch (err) {
    console.error('delete user failed', err);
    res.status(500).json({ error: 'failed to delete user' });
  }
});

app.listen(PORT, () => console.log(`user-service listening on ${PORT}`));
