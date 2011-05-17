/*=========================================================================
 Program:   OsiriX
 
 Copyright (c) OsiriX Team
 All rights reserved.
 Distributed under GNU - LGPL
 
 See http://www.osirix-viewer.com/copyright.html for details.
 
 This software is distributed WITHOUT ANY WARRANTY; without even
 the implied warranty of MERCHANTABILITY or FITNESS FOR A PARTICULAR
 PURPOSE.
 =========================================================================*/

#import "N3BezierCoreAdditions.h"


N3BezierCoreRef N3BezierCoreCreateCurveWithNodes(N3VectorArray vectors, CFIndex numVectors, N3BezierNodeStyle style)
{
    return N3BezierCoreCreateMutableCurveWithNodes(vectors, numVectors, style);
}

N3MutableBezierCoreRef N3BezierCoreCreateMutableCurveWithNodes(N3VectorArray vectors, CFIndex numVectors, N3BezierNodeStyle style)
{
	N3Vector p1, p2;
	long long  i, j;
	double xi, yi, zi;
	long long nb;
	double *px, *py, *pz;
	int ok;
    
	double *a, b, *c, *cx, *cy, *cz, *d, *g, *h;
	double bet, *gam;
	double aax, bbx, ccx, ddx, aay, bby, ccy, ddy, aaz, bbz, ccz, ddz; // coef of spline
    
    // get the new beziercore ready 
    N3MutableBezierCoreRef newBezierCore;
    N3Vector control1;
    N3Vector control2;
    N3Vector lastEndpoint;
    N3Vector endpoint;
    newBezierCore = N3BezierCoreCreateMutable();
    
    assert (numVectors >= 2);
    
    if (numVectors == 2) {
        N3BezierCoreAddSegment(newBezierCore, N3MoveToBezierCoreSegmentType, N3VectorZero, N3VectorZero, vectors[0]);
        N3BezierCoreAddSegment(newBezierCore, N3LineToBezierCoreSegmentType, N3VectorZero, N3VectorZero, vectors[1]);
        return newBezierCore;
    }
    
	// function spline S(x) = a x3 + bx2 + cx + d
	// with S continue, S1 continue, S2 continue.
	// smoothing of a closed polygon given by a list of points (x,y)
	// we compute a spline for x and a spline for y
	// where x and y are function of d where t is the distance between points
    
	// compute tridiag matrix
	//   | b1 c1 0 ...                   |   |  u1 |   |  r1 |
	//   | a2 b2 c2 0 ...                |   |  u2 |   |  r2 |
	//   |  0 a3 b3 c3 0 ...             | * | ... | = | ... |
	//   |                  ...          |   | ... |   | ... |
	//   |                an-1 bn-1 cn-1 |   | ... |   | ... |
	//   |                 0    an   bn  |   |  un |   |  rn |
	// bi = 4
	// resolution algorithm is taken from the book : Numerical recipes in C
    
	// initialization of different vectors
	// element number 0 is not used (except h[0])
	nb  = numVectors + 2;
	a   = malloc(nb*sizeof(double));	
	c   = malloc(nb*sizeof(double));	
	cx  = malloc(nb*sizeof(double));	
	cy  = malloc(nb*sizeof(double));	
	cz  = malloc(nb*sizeof(double));	
	d   = malloc(nb*sizeof(double));	
	g   = malloc(nb*sizeof(double));	
	gam = malloc(nb*sizeof(double));	
	h   = malloc(nb*sizeof(double));	
	px  = malloc(nb*sizeof(double));	
	py  = malloc(nb*sizeof(double));	
	pz  = malloc(nb*sizeof(double));	
    
	
	BOOL failed = NO;
	
	if( !a) failed = YES;
	if( !c) failed = YES;
	if( !cx) failed = YES;
	if( !cy) failed = YES;
	if( !cz) failed = YES;
	if( !d) failed = YES;
	if( !g) failed = YES;
	if( !gam) failed = YES;
	if( !h) failed = YES;
	if( !px) failed = YES;
	if( !py) failed = YES;
	if( !pz) failed = YES;
	
	if( failed)
	{
		free(a);
		free(c);
		free(cx);
		free(cy);
		free(cz);
		free(d);
		free(g);
		free(gam);
		free(h);
		free(px);
		free(py);
		free(pz);
		
        fprintf(stderr, "N3BezierCoreCreateMutableCurveWithNodes failed because it could not allocate enough memory\n");
		return NULL;
	}
	
	//initialisation
	for (i=0; i<nb; i++)
		h[i] = a[i] = cx[i] = d[i] = c[i] = cy[i] = cz[i] = g[i] = gam[i] = 0.0;
    
	// as a spline starts and ends with a line one adds two points
	// in order to have continuity in starting point
    if (style == N3BezierNodeOpenEndsStyle) {
        for (i=0; i<numVectors; i++)
        {
            px[i+1] = vectors[i].x;// * fZoom / 100;
            py[i+1] = vectors[i].y;// * fZoom / 100;
            pz[i+1] = vectors[i].z;// * fZoom / 100;
        }
        px[0] = 2.0*px[1] - px[2]; px[nb-1] = 2.0*px[nb-2] - px[nb-3];
        py[0] = 2.0*py[1] - py[2]; py[nb-1] = 2.0*py[nb-2] - py[nb-3];
        pz[0] = 2.0*pz[1] - pz[2]; pz[nb-1] = 2.0*pz[nb-2] - pz[nb-3];
    } else { // N3BezierNodeEndsMeetStyle
        for (i=0; i<numVectors; i++)
        {
            px[i+1] = vectors[i].x;// * fZoom / 100;
            py[i+1] = vectors[i].y;// * fZoom / 100;
            pz[i+1] = vectors[i].z;// * fZoom / 100;
        }
        px[0] = px[nb-3]; px[nb-1] = px[2];
        py[0] = py[nb-3]; py[nb-1] = py[2];
        pz[0] = pz[nb-3]; pz[nb-1] = pz[2];
    }

    
	// check all points are separate, if not do not smooth
	// this happens when the zoom factor is too small
	// so in this case the smooth is not useful
    
	ok=TRUE;
	if(nb<3) ok=FALSE;
    
//	for (i=1; i<nb; i++) 
//        if (px[i] == px[i-1] && py[i] == py[i-1] && pz[i] == pz[i-1]) {ok = FALSE; break;}
	if (ok == FALSE)
		failed = YES;
    
	if( failed)
	{
		free(a);
		free(c);
		free(cx);
		free(cy);
		free(cz);
		free(d);
		free(g);
		free(gam);
		free(h);
		free(px);
		free(py);
		free(pz);
		
        fprintf(stderr, "N3BezierCoreCreateMutableCurveWithNodes failed because some points overlapped\n");
		return NULL;
	}
    
	// define hi (distance between points) h0 distance between 0 and 1.
	// di distance of point i from start point
	for (i = 0; i<nb-1; i++)
	{
		xi = px[i+1] - px[i];
		yi = py[i+1] - py[i];
		zi = pz[i+1] - pz[i];
		h[i] = (double) sqrt(xi*xi + yi*yi + zi*zi);
		d[i+1] = d[i] + h[i];
	}
	
	// define ai and ci
	for (i=2; i<nb-1; i++) a[i] = 2.0 * h[i-1] / (h[i] + h[i-1]);
	for (i=1; i<nb-2; i++) c[i] = 2.0 * h[i] / (h[i] + h[i-1]);
    
	// define gi in function of x
	// gi+1 = 6 * Y[hi, hi+1, hi+2], 
	// Y[hi, hi+1, hi+2] = [(yi - yi+1)/(di - di+1) - (yi+1 - yi+2)/(di+1 - di+2)]
	//                      / (di - di+2)
	for (i=1; i<nb-1; i++) 
		g[i] = 6.0 * ( ((px[i-1] - px[i]) / (d[i-1] - d[i])) - ((px[i] - px[i+1]) / (d[i] - d[i+1])) ) / (d[i-1]-d[i+1]);
    
	// compute cx vector
	b=4; bet=4;
	cx[1] = g[1]/b;
	for (j=2; j<nb-1; j++)
	{
		gam[j] = c[j-1] / bet;
		bet = b - a[j] * gam[j];
		cx[j] = (g[j] - a[j] * cx[j-1]) / bet;
	}
	for (j=(nb-2); j>=1; j--) cx[j] -= gam[j+1] * cx[j+1];
    
	// define gi in function of y
	// gi+1 = 6 * Y[hi, hi+1, hi+2], 
	// Y[hi, hi+1, hi+2] = [(yi - yi+1)/(hi - hi+1) - (yi+1 - yi+2)/(hi+1 - hi+2)]
	//                      / (hi - hi+2)
	for (i=1; i<nb-1; i++)
		g[i] = 6.0 * ( ((py[i-1] - py[i]) / (d[i-1] - d[i])) - ((py[i] - py[i+1]) / (d[i] - d[i+1])) ) / (d[i-1]-d[i+1]);
    
	// compute cy vector
	b = 4.0; bet = 4.0;
	cy[1] = g[1] / b;
	for (j=2; j<nb-1; j++)
	{
		gam[j] = c[j-1] / bet;
		bet = b - a[j] * gam[j];
		cy[j] = (g[j] - a[j] * cy[j-1]) / bet;
	}
	for (j=(nb-2); j>=1; j--) cy[j] -= gam[j+1] * cy[j+1];
    
	// define gi in function of z
	// gi+1 = 6 * Y[hi, hi+1, hi+2], 
	// Y[hi, hi+1, hi+2] = [(yi - yi+1)/(hi - hi+1) - (yi+1 - yi+2)/(hi+1 - hi+2)]
	//                      / (hi - hi+2)
	for (i=1; i<nb-1; i++)
		g[i] = 6.0 * ( ((pz[i-1] - pz[i]) / (d[i-1] - d[i])) - ((pz[i] - pz[i+1]) / (d[i] - d[i+1])) ) / (d[i-1]-d[i+1]);
    
	// compute cz vector
	b = 4.0; bet = 4.0;
	cz[1] = g[1] / b;
	for (j=2; j<nb-1; j++)
	{
		gam[j] = c[j-1] / bet;
		bet = b - a[j] * gam[j];
		cz[j] = (g[j] - a[j] * cz[j-1]) / bet;
	}
	for (j=(nb-2); j>=1; j--) cz[j] -= gam[j+1] * cz[j+1];
    
	// OK we have the cx and cy and cz vectors, from that we can compute the
	// coeff of the polynoms for x and y and z andfor each interval
	// S(x) (xi, xi+1)  = ai + bi (x-xi) + ci (x-xi)2 + di (x-xi)3
	// di = (ci+1 - ci) / 3 hi
	// ai = yi
	// bi = ((ai+1 - ai) / hi) - (hi/3) (ci+1 + 2 ci)
    
    lastEndpoint = N3VectorMake(px[1], py[1], pz[1]);
    N3BezierCoreAddSegment(newBezierCore, N3MoveToBezierCoreSegmentType, N3VectorZero, N3VectorZero, lastEndpoint);
    
	// for each interval
	for (i=1; i<nb-2; i++)
	{
		// compute coef for x polynom
		ccx = cx[i];
		aax = px[i];
		ddx = (cx[i+1] - cx[i]) / (3.0 * h[i]);
		bbx = ((px[i+1] - px[i]) / h[i]) - (h[i] / 3.0) * (cx[i+1] + 2.0 * cx[i]);
        
		// compute coef for y polynom
		ccy = cy[i];
		aay = py[i];
		ddy = (cy[i+1] - cy[i]) / (3.0 * h[i]);
		bby = ((py[i+1] - py[i]) / h[i]) - (h[i] / 3.0) * (cy[i+1] + 2.0 * cy[i]);
        
		// compute coef for z polynom
		ccz = cz[i];
		aaz = pz[i];
		ddz = (cz[i+1] - cz[i]) / (3.0 * h[i]);
		bbz = ((pz[i+1] - pz[i]) / h[i]) - (h[i] / 3.0) * (cz[i+1] + 2.0 * cz[i]);
        
        //p.x = (aax + bbx * (double)j + ccx * (double)(j * j) + ddx * (double)(j * j * j));
        
        endpoint.x = aax + bbx*h[i] + ccx*h[i]*h[i] + ddx*h[i]*h[i]*h[i];
        control1.x = lastEndpoint.x + ((bbx*h[i]) / 3.0);
        control2.x = endpoint.x - (((bbx + 2.0*ccx*h[i] + 3.0*ddx*h[i]*h[i]) * h[i]) / 3.0);
        
        endpoint.y = aay + bby*h[i] + ccy*h[i]*h[i] + ddy*h[i]*h[i]*h[i];
        control1.y = lastEndpoint.y + ((bby*h[i]) / 3.0);
        control2.y = endpoint.y - (((bby + 2.0*ccy*h[i] + 3.0*ddy*h[i]*h[i]) * h[i]) / 3.0);
        
        endpoint.z = aaz + bbz*h[i] + ccz*h[i]*h[i] + ddz*h[i]*h[i]*h[i];
        control1.z = lastEndpoint.z + ((bbz*h[i]) / 3.0);
        control2.z = endpoint.z - (((bbz + 2.0*ccz*h[i] + 3.0*ddz*h[i]*h[i]) * h[i]) / 3.0);
        
        N3BezierCoreAddSegment(newBezierCore, N3CurveToBezierCoreSegmentType, control1, control2, endpoint);
        lastEndpoint = endpoint;
    }//endfor each interval
    
	// delete dynamic structures
	free(a);
	free(c);
	free(cx);
    free(cy);
    free(cz);
	free(d);
	free(g);
	free(gam);
	free(h);
	free(px);
	free(py);
	free(pz);
    
	return newBezierCore;
}

N3Vector N3BezierCoreVectorAtStart(N3BezierCoreRef bezierCore)
{
    N3Vector moveTo;
    
    if (N3BezierCoreSegmentCount(bezierCore) == 0) {
        return N3VectorZero;
    }
    
    N3BezierCoreGetSegmentAtIndex(bezierCore, 0, NULL, NULL, &moveTo);
    return moveTo;
}

N3Vector N3BezierCoreVectorAtEnd(N3BezierCoreRef bezierCore)
{
    N3Vector endPoint;
    
    if (N3BezierCoreSegmentCount(bezierCore) == 0) {
        return N3VectorZero;
    }
    
    N3BezierCoreGetSegmentAtIndex(bezierCore, N3BezierCoreSegmentCount(bezierCore) - 1, NULL, NULL, &endPoint);
    return endPoint;
}


N3Vector N3BezierCoreTangentAtStart(N3BezierCoreRef bezierCore)
{
    N3Vector moveTo;
    N3Vector endPoint;
    N3Vector control1;
    
    if (N3BezierCoreSegmentCount(bezierCore) < 2) {
        return N3VectorZero;
    }
    
    N3BezierCoreGetSegmentAtIndex(bezierCore, 0, NULL, NULL, &moveTo);
    
    if (N3BezierCoreGetSegmentAtIndex(bezierCore, 1, &control1, NULL, &endPoint) == N3CurveToBezierCoreSegmentType) {
        return N3VectorNormalize(N3VectorSubtract(endPoint, control1));
    } else {
        return N3VectorNormalize(N3VectorSubtract(endPoint, moveTo));
    }
}

N3Vector N3BezierCoreTangentAtEnd(N3BezierCoreRef bezierCore)
{
    N3Vector prevEndPoint;
    N3Vector endPoint;
    N3Vector control2;
    CFIndex segmentCount;
    
    segmentCount = N3BezierCoreSegmentCount(bezierCore);
    if (segmentCount < 2) {
        return N3VectorZero;
    }    
    
    if (N3BezierCoreGetSegmentAtIndex(bezierCore, segmentCount - 1, NULL, &control2, &endPoint) == N3CurveToBezierCoreSegmentType) {
        return N3VectorNormalize(N3VectorSubtract(endPoint, control2));
    } else {
        N3BezierCoreGetSegmentAtIndex(bezierCore, segmentCount - 2, NULL, NULL, &prevEndPoint);
        return N3VectorNormalize(N3VectorSubtract(endPoint, prevEndPoint));
    }    
}

CGFloat N3BezierCoreRelativePositionClosestToVector(N3BezierCoreRef bezierCore, N3Vector vector, N3VectorPointer closestVector, CGFloat *distance)
{
    N3BezierCoreIteratorRef bezierIterator;
    N3BezierCoreRef flattenedBezier;
    N3Vector start;
    N3Vector end;
    N3Vector segment;
	N3Vector segmentDirection;
    N3Vector translatedVector;
	N3Vector bestVector;
	N3BezierCoreSegmentType segmentType;
    CGFloat tempDistance;
    CGFloat bestRelativePosition;
    CGFloat bestDistance;
    CGFloat projectedDistance;
    CGFloat segmentLength;
    CGFloat traveledDistance;
    
    if (N3BezierCoreSegmentCount(bezierCore) < 2) {
        return 0.0;
    }
    
    if (N3BezierCoreHasCurve(bezierCore)) {
        flattenedBezier = N3BezierCoreCreateMutableCopy(bezierCore);
        N3BezierCoreFlatten((N3MutableBezierCoreRef)flattenedBezier, N3BezierDefaultFlatness);
    } else {
        flattenedBezier = N3BezierCoreRetain(bezierCore);
    }

    bezierIterator = N3BezierCoreIteratorCreateWithBezierCore(flattenedBezier);
    
    bestDistance = CGFLOAT_MAX;
    bestRelativePosition = 0.0;
    traveledDistance = 0.0;
    
    N3BezierCoreIteratorGetNextSegment(bezierIterator, NULL, NULL, &end);
    
    while (!N3BezierCoreIteratorIsAtEnd(bezierIterator)) {
        start = end;
        segmentType = N3BezierCoreIteratorGetNextSegment(bezierIterator, NULL, NULL, &end);
        
        segment = N3VectorSubtract(end, start);
        translatedVector = N3VectorSubtract(vector, start);
        segmentLength = N3VectorLength(segment);
		segmentDirection = N3VectorScalarMultiply(segment, 1.0/segmentLength);
        
        projectedDistance = N3VectorDotProduct(translatedVector, segmentDirection);
        
		if (segmentType != N3MoveToBezierCoreSegmentType) {
			if (projectedDistance >= 0 && projectedDistance <= segmentLength) {
				tempDistance = N3VectorLength(N3VectorSubtract(translatedVector, N3VectorScalarMultiply(segmentDirection, projectedDistance)));
				if (tempDistance < bestDistance) {
					bestDistance = tempDistance;
					bestRelativePosition = traveledDistance + projectedDistance;
					bestVector = N3VectorAdd(start, N3VectorScalarMultiply(segmentDirection, projectedDistance));
				}
			} else if (projectedDistance < 0) {
				tempDistance = N3VectorDistance(start, vector);
				if (tempDistance < bestDistance) {
					bestDistance = tempDistance;
					bestRelativePosition = traveledDistance;
					bestVector = start;
				} 
			} else {
				tempDistance = N3VectorDistance(end, vector);
				if (tempDistance < bestDistance) {
					bestDistance = tempDistance;
					bestRelativePosition = traveledDistance + segmentLength;
					bestVector = end;
				} 
			}
		
			traveledDistance += segmentLength;
		}
    }
    
    bestRelativePosition /= N3BezierCoreLength(flattenedBezier);    
    
    N3BezierCoreRelease(flattenedBezier);
    N3BezierCoreIteratorRelease(bezierIterator);
    
    if (distance) {
        *distance = bestDistance;
    }
	if (closestVector) {
		*closestVector = bestVector;
	}
    
    return bestRelativePosition;
}

CGFloat N3BezierCoreRelativePositionClosestToLine(N3BezierCoreRef bezierCore, N3Line line, N3VectorPointer closestVector, CGFloat *distance)
{
    N3BezierCoreIteratorRef bezierIterator;
    N3BezierCoreRef flattenedBezier;
    N3Vector start;
    N3Vector end;
    N3Line segment;
    N3Vector translatedVector;
    N3Vector closestPoint;
    N3Vector bestVector;
	N3BezierCoreSegmentType segmentType;
    CGFloat mu;
    CGFloat tempDistance;
    CGFloat bestRelativePosition;
    CGFloat bestDistance;
    CGFloat traveledDistance;
    CGFloat segmentLength;

    if (N3BezierCoreSegmentCount(bezierCore) < 2) {
        return 0.0;
    }
    
    if (N3BezierCoreHasCurve(bezierCore)) {
        flattenedBezier = N3BezierCoreCreateMutableCopy(bezierCore);
        N3BezierCoreFlatten((N3MutableBezierCoreRef)flattenedBezier, N3BezierDefaultFlatness);
    } else {
        flattenedBezier = N3BezierCoreRetain(bezierCore);
    }

    bezierIterator = N3BezierCoreIteratorCreateWithBezierCore(flattenedBezier);
    
    bestDistance = CGFLOAT_MAX;
    bestRelativePosition = 0.0;
    traveledDistance = 0.0;
    N3BezierCoreIteratorGetNextSegment(bezierIterator, NULL, NULL, &end);
    bestVector = end;

    while (!N3BezierCoreIteratorIsAtEnd(bezierIterator)) {
        start = end;
        segmentType = N3BezierCoreIteratorGetNextSegment(bezierIterator, NULL, NULL, &end);
        
        segmentLength = N3VectorDistance(start, end);
        
        if (segmentLength > 0.0 && segmentType != N3MoveToBezierCoreSegmentType) {
            segment = N3LineMakeFromPoints(start, end);
            tempDistance = N3LineClosestPoints(segment, line, &closestPoint, NULL);
            
            if (tempDistance < bestDistance) {
                mu = N3VectorDotProduct(N3VectorSubtract(end, start), N3VectorSubtract(closestPoint, start)) / (segmentLength*segmentLength);
                
                if (mu < 0.0) {
                    tempDistance = N3VectorDistanceToLine(start, line);
                    if (tempDistance < bestDistance) {
                        bestDistance = tempDistance;
                        bestRelativePosition = traveledDistance;
                        bestVector = start;
                    }
                } else if (mu > 1.0) {
                    tempDistance = N3VectorDistanceToLine(end, line);
                    if (tempDistance < bestDistance) {
                        bestDistance = tempDistance;
                        bestRelativePosition = traveledDistance + segmentLength;
                        bestVector = end;
                    }
                } else {
                    bestDistance = tempDistance;
                    bestRelativePosition = traveledDistance + (segmentLength * mu);
                    bestVector = closestPoint;
                }
            }
            traveledDistance += segmentLength;
        }
    }
    
    bestRelativePosition /= N3BezierCoreLength(flattenedBezier);    

    N3BezierCoreRelease(flattenedBezier);
    N3BezierCoreIteratorRelease(bezierIterator);
    
    if (closestVector) {
        *closestVector = bestVector;
    }
    if (distance) {
        *distance = bestDistance;
    }
    
    return bestRelativePosition;
}

CFIndex N3BezierCoreGetVectorInfo(N3BezierCoreRef bezierCore, CGFloat spacing, CGFloat startingDistance, N3Vector initialNormal,
                                               N3VectorArray vectors, N3VectorArray tangents, N3VectorArray normals, CFIndex numVectors)
{
    N3BezierCoreRef flattenedBezierCore;
    N3BezierCoreIteratorRef bezierCoreIterator;
    N3Vector nextVector;
    N3Vector startVector;
    N3Vector endVector;
    N3Vector previousTangentVector;
    N3Vector nextTangentVector;
    N3Vector tangentVector;
    N3Vector startTangentVector;
    N3Vector endTangentVector;
    N3Vector previousNormalVector;
    N3Vector nextNormalVector;
    N3Vector normalVector;
    N3Vector startNormalVector;
    N3Vector endNormalVector;
    N3Vector segmentDirection;
    N3Vector nextSegmentDirection;
    CGFloat segmentLength;
    CGFloat distanceTraveled;
    CGFloat totalDistanceTraveled;
    CGFloat extraDistance;
    CFIndex i;
    bool done;
	
    if (numVectors == 0 || N3BezierCoreSegmentCount(bezierCore) < 2) {
        return 0;
    }
    
	assert(normals == NULL || N3BezierCoreSubpathCount(bezierCore) == 1); // this only works when there is a single subpath
	assert(N3BezierCoreSubpathCount(bezierCore) == 1); // TODO! I should fix this to be able to handle moveTo as long as normals don't matter

    if (N3BezierCoreHasCurve(bezierCore)) {
        flattenedBezierCore = N3BezierCoreCreateMutableCopy(bezierCore);
        N3BezierCoreSubdivide((N3MutableBezierCoreRef)flattenedBezierCore, N3BezierDefaultSubdivideSegmentLength);
        N3BezierCoreFlatten((N3MutableBezierCoreRef)flattenedBezierCore, N3BezierDefaultFlatness);
    } else {
        flattenedBezierCore = N3BezierCoreRetain(bezierCore);
    }    
    
    bezierCoreIterator = N3BezierCoreIteratorCreateWithBezierCore(flattenedBezierCore);
    N3BezierCoreRelease(flattenedBezierCore);
    flattenedBezierCore = NULL;
    
    extraDistance = startingDistance; // distance that was traveled past the last point
    totalDistanceTraveled = 0.0;
    done = false;
	i = 0;
    startVector = N3VectorZero;
    endVector = N3VectorZero;
    
    N3BezierCoreIteratorGetNextSegment(bezierCoreIterator, NULL, NULL, &startVector);
	N3BezierCoreIteratorGetNextSegment(bezierCoreIterator, NULL, NULL, &endVector);
    segmentDirection = N3VectorNormalize(N3VectorSubtract(endVector, startVector));
    segmentLength = N3VectorDistance(endVector, startVector);
    
    normalVector = N3VectorNormalize(N3VectorSubtract(initialNormal, N3VectorProject(initialNormal, segmentDirection)));
    if(N3VectorEqualToVector(normalVector, N3VectorZero)) {
        normalVector = N3VectorNormalize(N3VectorCrossProduct(N3VectorMake(-1.0, 0.0, 0.0), segmentDirection));
        if(N3VectorEqualToVector(normalVector, N3VectorZero)) {
            normalVector = N3VectorNormalize(N3VectorCrossProduct(N3VectorMake(0.0, 1.0, 0.0), segmentDirection));
        }
    }
    
    previousNormalVector = normalVector;
    tangentVector = segmentDirection;
    previousTangentVector = tangentVector;
    
	while (done == false) {
		distanceTraveled = extraDistance;
        
        if (N3BezierCoreIteratorIsAtEnd(bezierCoreIterator)) {
            nextNormalVector = normalVector;
            nextTangentVector = tangentVector;
            nextVector = endVector;
            done = true;
        } else {
            N3BezierCoreIteratorGetNextSegment(bezierCoreIterator, NULL, NULL, &nextVector);
            nextSegmentDirection = N3VectorNormalize(N3VectorSubtract(nextVector, endVector));
            nextNormalVector = N3VectorBend(normalVector, segmentDirection, nextSegmentDirection);
            nextNormalVector = N3VectorSubtract(nextNormalVector, N3VectorProject(nextNormalVector, nextSegmentDirection)); // make sure the new vector is really normal
            nextNormalVector = N3VectorNormalize(nextNormalVector);

            nextTangentVector = nextSegmentDirection;
        }
        startNormalVector = N3VectorNormalize(N3VectorScalarMultiply(N3VectorAdd(previousNormalVector, normalVector), 0.5)); 
        endNormalVector = N3VectorNormalize(N3VectorScalarMultiply(N3VectorAdd(nextNormalVector, normalVector), 0.5)); 
        
        startTangentVector = N3VectorNormalize(N3VectorScalarMultiply(N3VectorAdd(previousTangentVector, tangentVector), 0.5)); 
        endTangentVector = N3VectorNormalize(N3VectorScalarMultiply(N3VectorAdd(nextTangentVector, tangentVector), 0.5)); 
        
		while(distanceTraveled < segmentLength)
		{
            if (vectors) {
                vectors[i] = N3VectorAdd(startVector, N3VectorScalarMultiply(segmentDirection, distanceTraveled));
            }
            if (tangents) {
                tangents[i] = segmentDirection;
                tangents[i] = N3VectorNormalize(N3VectorAdd(N3VectorScalarMultiply(startTangentVector, 1.0-distanceTraveled/segmentLength), N3VectorScalarMultiply(endTangentVector, distanceTraveled/segmentLength)));
                
            }
            if (normals) {
                normals[i] = N3VectorNormalize(N3VectorAdd(N3VectorScalarMultiply(startNormalVector, 1.0-distanceTraveled/segmentLength), N3VectorScalarMultiply(endNormalVector, distanceTraveled/segmentLength)));
            }
            i++;
            if (i >= numVectors) {
                N3BezierCoreIteratorRelease(bezierCoreIterator);
                return i;
            }
            
            distanceTraveled += spacing;
            totalDistanceTraveled += spacing;
		}
		
		extraDistance = distanceTraveled - segmentLength;
        
        previousNormalVector = normalVector;
        normalVector = nextNormalVector;
        previousTangentVector = tangentVector;
        tangentVector = nextTangentVector;
        segmentDirection = nextSegmentDirection;
        startVector = endVector;
        endVector = nextVector;
        segmentLength = N3VectorDistance(startVector, endVector);
        
	}
	
    N3BezierCoreIteratorRelease(bezierCoreIterator);
	return i;
}

N3Vector N3BezierCoreNormalAtEndWithInitialNormal(N3BezierCoreRef bezierCore, N3Vector initialNormal)
{
    N3BezierCoreRef flattenedBezierCore;
    N3BezierCoreIteratorRef bezierCoreIterator;
    N3Vector normalVector;
    N3Vector segment;
    N3Vector prevSegment;
    N3Vector start;
    N3Vector end;
    
	assert(N3BezierCoreSubpathCount(bezierCore) == 1); // this only works when there is a single subpath

    if (N3BezierCoreSegmentCount(bezierCore) < 2) {
        return initialNormal;
    }
    
    if (N3BezierCoreHasCurve(bezierCore)) {
        flattenedBezierCore = N3BezierCoreCreateMutableCopy(bezierCore);
        N3BezierCoreFlatten((N3MutableBezierCoreRef)flattenedBezierCore, N3BezierDefaultFlatness);
    } else {
        flattenedBezierCore = N3BezierCoreRetain(bezierCore);
    }
    bezierCoreIterator = N3BezierCoreIteratorCreateWithBezierCore(flattenedBezierCore);
    N3BezierCoreRelease(flattenedBezierCore);
    flattenedBezierCore = NULL;
    
    
    N3BezierCoreIteratorGetNextSegment(bezierCoreIterator, NULL, NULL, &start);
    N3BezierCoreIteratorGetNextSegment(bezierCoreIterator, NULL, NULL, &end);
    prevSegment = N3VectorSubtract(end, start);
    
    normalVector = N3VectorNormalize(N3VectorSubtract(initialNormal, N3VectorProject(initialNormal, prevSegment)));
    if(N3VectorEqualToVector(normalVector, N3VectorZero)) {
        normalVector = N3VectorNormalize(N3VectorCrossProduct(N3VectorMake(-1.0, 0.0, 0.0), prevSegment));
        if(N3VectorEqualToVector(normalVector, N3VectorZero)) {
            normalVector = N3VectorNormalize(N3VectorCrossProduct(N3VectorMake(0.0, 1.0, 0.0), prevSegment));
        }
    }
    
    while (!N3BezierCoreIteratorIsAtEnd(bezierCoreIterator)) {
        start = end;
        N3BezierCoreIteratorGetNextSegment(bezierCoreIterator, NULL, NULL, &end);
        
        segment = N3VectorSubtract(end, start);
        normalVector = N3VectorBend(normalVector, prevSegment, segment);
        normalVector = N3VectorSubtract(normalVector, N3VectorProject(normalVector, segment)); // make sure the new vector is really normal
        normalVector = N3VectorNormalize(normalVector);

        prevSegment = segment;
    }
    
    N3BezierCoreIteratorRelease(bezierCoreIterator);
    return normalVector;
}

N3BezierCoreRef N3BezierCoreCreateOutline(N3BezierCoreRef bezierCore, CGFloat distance, CGFloat spacing, N3Vector initialNormal)
{
    return N3BezierCoreCreateMutableOutline(bezierCore, distance, spacing, initialNormal);
}

N3MutableBezierCoreRef N3BezierCoreCreateMutableOutline(N3BezierCoreRef bezierCore, CGFloat distance, CGFloat spacing, N3Vector initialNormal)
{
    N3BezierCoreRef flattenedBezierCore;
    N3MutableBezierCoreRef outlineBezier;
    N3Vector endpoint;
    N3Vector endpointNormal;
    CGFloat length;
    NSInteger i;
    NSUInteger numVectors;
    N3VectorArray vectors;
    N3VectorArray normals;
    N3VectorArray scaledNormals;
    N3VectorArray side;
    
	assert(N3BezierCoreSubpathCount(bezierCore) == 1); // this only works when there is a single subpath

    if (N3BezierCoreSegmentCount(bezierCore) < 2) {
        return NULL;
    }
    
    if (N3BezierCoreHasCurve(bezierCore)) {
        flattenedBezierCore = N3BezierCoreCreateMutableCopy(bezierCore);
        N3BezierCoreSubdivide((N3MutableBezierCoreRef)flattenedBezierCore, N3BezierDefaultSubdivideSegmentLength);
        N3BezierCoreFlatten((N3MutableBezierCoreRef)flattenedBezierCore, N3BezierDefaultFlatness);
    } else {
        flattenedBezierCore = N3BezierCoreRetain(bezierCore); 
    }
        
    length = N3BezierCoreLength(flattenedBezierCore);
    
    if (spacing * 2 >= length) {
        N3BezierCoreRelease(flattenedBezierCore);
        return NULL;
    }
    
    numVectors = length/spacing + 1.0;
    
    vectors = malloc(numVectors * sizeof(N3Vector));
    normals = malloc(numVectors * sizeof(N3Vector));
    scaledNormals = malloc(numVectors * sizeof(N3Vector));
    side = malloc(numVectors * sizeof(N3Vector));
    outlineBezier = N3BezierCoreCreateMutable();
    
    numVectors = N3BezierCoreGetVectorInfo(flattenedBezierCore, spacing, 0, initialNormal, vectors, NULL, normals, numVectors);
    N3BezierCoreGetSegmentAtIndex(flattenedBezierCore, N3BezierCoreSegmentCount(flattenedBezierCore) - 1, NULL, NULL, &endpoint);
    endpointNormal = N3VectorNormalize(N3VectorSubtract(normals[numVectors-1], N3VectorProject(normals[numVectors-1], N3BezierCoreTangentAtEnd(flattenedBezierCore))));
    endpointNormal = N3VectorScalarMultiply(endpointNormal, distance);
    
    memcpy(scaledNormals, normals, numVectors * sizeof(N3Vector));
    N3VectorScalarMultiplyVectors(distance, scaledNormals, numVectors);

    memcpy(side, vectors, numVectors * sizeof(N3Vector));
    N3VectorAddVectors(side, scaledNormals, numVectors);
    
    N3BezierCoreAddSegment(outlineBezier, N3MoveToBezierCoreSegmentType, N3VectorZero, N3VectorZero, side[0]);
    for (i = 1; i < numVectors; i++) {
        N3BezierCoreAddSegment(outlineBezier, N3LineToBezierCoreSegmentType, N3VectorZero, N3VectorZero, side[i]);
    }
    N3BezierCoreAddSegment(outlineBezier, N3LineToBezierCoreSegmentType, N3VectorZero, N3VectorZero, N3VectorAdd(endpoint, endpointNormal));
                                                
    memcpy(scaledNormals, normals, numVectors * sizeof(N3Vector));
    N3VectorScalarMultiplyVectors(-distance, scaledNormals, numVectors);

    memcpy(side, vectors, numVectors * sizeof(N3Vector));
    N3VectorAddVectors(side, scaledNormals, numVectors);

    N3BezierCoreAddSegment(outlineBezier, N3MoveToBezierCoreSegmentType, N3VectorZero, N3VectorZero, side[0]);
    for (i = 1; i < numVectors; i++) {
        N3BezierCoreAddSegment(outlineBezier, N3LineToBezierCoreSegmentType, N3VectorZero, N3VectorZero, side[i]);
    }
    N3BezierCoreAddSegment(outlineBezier, N3LineToBezierCoreSegmentType, N3VectorZero, N3VectorZero, N3VectorAdd(endpoint, N3VectorInvert(endpointNormal)));
    
    free(vectors);
    free(normals);
    free(scaledNormals);
    free(side);
    
    N3BezierCoreRelease(flattenedBezierCore);
    
    return outlineBezier;
}

CGFloat N3BezierCoreLengthToSegmentAtIndex(N3BezierCoreRef bezierCore, CFIndex index, CGFloat flatness) // the length up to and including the segment at index
{
    N3MutableBezierCoreRef shortBezierCore;
    N3BezierCoreIteratorRef bezierCoreIterator;
    N3BezierCoreSegmentType segmentType;
	N3BezierCoreRef flattenedShortBezierCore;
    N3Vector endpoint;
    N3Vector control1;
    N3Vector control2;
    CGFloat length;
    CFIndex i;
    
    assert(index < N3BezierCoreSegmentCount(bezierCore));
    
    bezierCoreIterator = N3BezierCoreIteratorCreateWithBezierCore(bezierCore);
    shortBezierCore = N3BezierCoreCreateMutable();
    
    for (i = 0; i <= index; i++) {
        segmentType = N3BezierCoreIteratorGetNextSegment(bezierCoreIterator, &control1, &control2, &endpoint);
        N3BezierCoreAddSegment(shortBezierCore, segmentType, control1, control2, endpoint);
    }
    
	flattenedShortBezierCore = N3BezierCoreCreateFlattenedMutableCopy(shortBezierCore, flatness);
    length = N3BezierCoreLength(flattenedShortBezierCore);
	
    N3BezierCoreRelease(shortBezierCore);
	N3BezierCoreRelease(flattenedShortBezierCore);
    N3BezierCoreIteratorRelease(bezierCoreIterator);
    
    return length;
}

CFIndex N3BezierCoreSegmentLengths(N3BezierCoreRef bezierCore, CGFloat *lengths, CFIndex numLengths, CGFloat flatness) // returns the number of lengths set
{
	N3BezierCoreIteratorRef bezierCoreIterator;
	N3MutableBezierCoreRef segmentBezierCore;
	N3MutableBezierCoreRef flatenedSegmentBezierCore;
	N3Vector prevEndpoint;
	N3Vector control1;
	N3Vector control2;
	N3Vector endpoint;
	N3BezierCoreSegmentType segmentType;
	CFIndex i;

	bezierCoreIterator = N3BezierCoreIteratorCreateWithBezierCore(bezierCore);
	
	if (numLengths > 0 && N3BezierCoreSegmentCount(bezierCore) > 0) {
		lengths[0] = 0.0;
	} else {
		return 0;
	}

	
	N3BezierCoreIteratorGetNextSegment(bezierCoreIterator, NULL, NULL, &prevEndpoint);
	
	for (i = 1; i < MIN(numLengths, N3BezierCoreSegmentCount(bezierCore)); i++) {
		segmentType = N3BezierCoreIteratorGetNextSegment(bezierCoreIterator, &control1, &control2, &endpoint);
		
		segmentBezierCore = N3BezierCoreCreateMutable();
		N3BezierCoreAddSegment(segmentBezierCore, N3MoveToBezierCoreSegmentType, N3VectorZero, N3VectorZero, prevEndpoint);
		N3BezierCoreAddSegment(segmentBezierCore, segmentType, control1, control2, endpoint);
		
		flatenedSegmentBezierCore = N3BezierCoreCreateFlattenedMutableCopy(segmentBezierCore, flatness);
		lengths[i] = N3BezierCoreLength(flatenedSegmentBezierCore);
		
		N3BezierCoreRelease(segmentBezierCore);
		N3BezierCoreRelease(flatenedSegmentBezierCore);
	}
	
	N3BezierCoreIteratorRelease(bezierCoreIterator);

	return i;
}

CFIndex N3BezierCoreCountIntersectionsWithPlane(N3BezierCoreRef bezierCore, N3Plane plane)
{
	N3BezierCoreRef flattenedBezierCore;
	N3BezierCoreIteratorRef bezierCoreIterator;
    N3Vector endpoint;
    N3Vector prevEndpoint;
	N3BezierCoreSegmentType segmentType;
    NSInteger count;
    NSUInteger numVectors;
    
    if (N3BezierCoreSegmentCount(bezierCore) < 2) {
        return 0;
    }
    
    if (N3BezierCoreHasCurve(bezierCore)) {
        flattenedBezierCore = N3BezierCoreCreateMutableCopy(bezierCore);
        N3BezierCoreSubdivide((N3MutableBezierCoreRef)flattenedBezierCore, N3BezierDefaultSubdivideSegmentLength);
        N3BezierCoreFlatten((N3MutableBezierCoreRef)flattenedBezierCore, N3BezierDefaultFlatness);
    } else {
        flattenedBezierCore = N3BezierCoreRetain(bezierCore); 
    }
	bezierCoreIterator = N3BezierCoreIteratorCreateWithBezierCore(flattenedBezierCore);
    N3BezierCoreRelease(flattenedBezierCore);
    flattenedBezierCore = NULL;
	count = 0;
	
	N3BezierCoreIteratorGetNextSegment(bezierCoreIterator, NULL, NULL, &prevEndpoint);
	
	while (!N3BezierCoreIteratorIsAtEnd(bezierCoreIterator)) {
		segmentType = N3BezierCoreIteratorGetNextSegment(bezierCoreIterator, NULL, NULL, &endpoint);
		if (segmentType != N3MoveToBezierCoreSegmentType && N3PlaneIsBetweenVectors(plane, endpoint, prevEndpoint)) {
			count++;
		}
		prevEndpoint = endpoint;
	}
	N3BezierCoreIteratorRelease(bezierCoreIterator);
	return count;
}


CFIndex N3BezierCoreIntersectionsWithPlane(N3BezierCoreRef bezierCore, N3Plane plane, N3VectorArray intersections, CGFloat *relativePositions, CFIndex numVectors)
{
	N3BezierCoreRef flattenedBezierCore;
	N3BezierCoreIteratorRef bezierCoreIterator;
    N3Vector endpoint;
    N3Vector prevEndpoint;
	N3Vector segment;
	N3Vector intersection;
	N3BezierCoreSegmentType segmentType;
    CGFloat length;
	CGFloat distance;
    NSInteger count;
    
    if (N3BezierCoreSegmentCount(bezierCore) < 2) {
        return 0;
    }
    
    if (N3BezierCoreHasCurve(bezierCore)) {
        flattenedBezierCore = N3BezierCoreCreateMutableCopy(bezierCore);
        N3BezierCoreSubdivide((N3MutableBezierCoreRef)flattenedBezierCore, N3BezierDefaultSubdivideSegmentLength);
        N3BezierCoreFlatten((N3MutableBezierCoreRef)flattenedBezierCore, N3BezierDefaultFlatness);
    } else {
        flattenedBezierCore = N3BezierCoreRetain(bezierCore); 
    }
    length = N3BezierCoreLength(flattenedBezierCore);
	bezierCoreIterator = N3BezierCoreIteratorCreateWithBezierCore(flattenedBezierCore);
    N3BezierCoreRelease(flattenedBezierCore);
    flattenedBezierCore = NULL;
	distance = 0.0; 
	count = 0;
	
	N3BezierCoreIteratorGetNextSegment(bezierCoreIterator, NULL, NULL, &prevEndpoint);
	
	while (!N3BezierCoreIteratorIsAtEnd(bezierCoreIterator) && count < numVectors) {
		segmentType = N3BezierCoreIteratorGetNextSegment(bezierCoreIterator, NULL, NULL, &endpoint);
		if (N3PlaneIsBetweenVectors(plane, endpoint, prevEndpoint)) {
			if (segmentType != N3MoveToBezierCoreSegmentType) {
				intersection = N3LineIntersectionWithPlane(N3LineMakeFromPoints(prevEndpoint, endpoint), plane);
				if (intersections) {
					intersections[count] = intersection;
				}
				if (relativePositions) {
					relativePositions[count] = (distance + N3VectorDistance(prevEndpoint, intersection))/length;
				}
				count++;
			}
		}
		distance += N3VectorDistance(prevEndpoint, endpoint);
		prevEndpoint = endpoint;
	}
	N3BezierCoreIteratorRelease(bezierCoreIterator);
	return count;	
}


N3MutableBezierCoreRef N3BezierCoreCreateMutableWithEndpointsAtPlaneIntersections(N3BezierCoreRef bezierCore, N3Plane plane)
{
    N3BezierCoreRef flattenedBezierCore;
	N3BezierCoreIteratorRef bezierCoreIterator;
    N3MutableBezierCoreRef newBezierCore;
	N3BezierCoreSegmentType segmentType;
    N3Vector endpoint;
    N3Vector prevEndpoint;
	N3Vector segment;
	N3Vector intersection;
    
    if (N3BezierCoreSegmentCount(bezierCore) < 2) {
        return N3BezierCoreCreateMutableCopy(bezierCore);
    }
    
    if (N3BezierCoreHasCurve(bezierCore)) {
        flattenedBezierCore = N3BezierCoreCreateMutableCopy(bezierCore);
        N3BezierCoreFlatten((N3MutableBezierCoreRef)flattenedBezierCore, N3BezierDefaultFlatness);
    } else {
        flattenedBezierCore = N3BezierCoreRetain(bezierCore); 
    }
    bezierCoreIterator = N3BezierCoreIteratorCreateWithBezierCore(flattenedBezierCore);
    N3BezierCoreRelease(flattenedBezierCore);
    flattenedBezierCore = NULL;
    newBezierCore = N3BezierCoreCreateMutable();
    
    N3BezierCoreIteratorGetNextSegment(bezierCoreIterator, NULL, NULL, &prevEndpoint);
    N3BezierCoreAddSegment(newBezierCore, N3MoveToBezierCoreSegmentType, N3VectorZero, N3VectorZero, prevEndpoint);

    while (!N3BezierCoreIteratorIsAtEnd(bezierCoreIterator)) {
		segmentType = N3BezierCoreIteratorGetNextSegment(bezierCoreIterator, NULL, NULL, &endpoint);
		if (segmentType != N3MoveToBezierCoreSegmentType && N3PlaneIsBetweenVectors(plane, endpoint, prevEndpoint)) {
            intersection = N3LineIntersectionWithPlane(N3LineMakeFromPoints(prevEndpoint, endpoint), plane);
            N3BezierCoreAddSegment(newBezierCore, N3LineToBezierCoreSegmentType, N3VectorZero, N3VectorZero, intersection);
		}
        
        N3BezierCoreAddSegment(newBezierCore, segmentType, N3VectorZero, N3VectorZero, endpoint);
		prevEndpoint = endpoint;
	}
    
    N3BezierCoreIteratorRelease(bezierCoreIterator);
    return newBezierCore;
}

N3Plane N3BezierCoreLeastSquaresPlane(N3BezierCoreRef bezierCore)
{
    N3BezierCoreRef flattenedBezierCore;
	N3BezierCoreIteratorRef bezierCoreIterator;
    N3VectorArray endpoints;
    N3Plane plane;
    CFIndex segmentCount;
    CFIndex i;

    if (N3BezierCoreHasCurve(bezierCore)) {
        flattenedBezierCore = N3BezierCoreCreateMutableCopy(bezierCore);
        N3BezierCoreFlatten((N3MutableBezierCoreRef)flattenedBezierCore, N3BezierDefaultFlatness);
    } else {
        flattenedBezierCore = N3BezierCoreRetain(bezierCore); 
    }
    
    segmentCount = N3BezierCoreSegmentCount(flattenedBezierCore);
    endpoints = malloc(segmentCount * sizeof(N3Vector));
    bezierCoreIterator = N3BezierCoreIteratorCreateWithBezierCore(flattenedBezierCore);
    N3BezierCoreRelease(flattenedBezierCore);
    flattenedBezierCore = NULL;
    
    for (i = 0; !N3BezierCoreIteratorIsAtEnd(bezierCoreIterator); i++) {
        N3BezierCoreIteratorGetNextSegment(bezierCoreIterator, NULL, NULL, &endpoints[i]);
    }
    
    N3BezierCoreIteratorRelease(bezierCoreIterator);
    
    plane = N3PlaneLeastSquaresPlaneFromPoints(endpoints, segmentCount);
    
    free(endpoints);
    return plane;
}

CGFloat N3BezierCoreMeanDistanceToPlane(N3BezierCoreRef bezierCore, N3Plane plane)
{
    N3BezierCoreRef flattenedBezierCore;
	N3BezierCoreIteratorRef bezierCoreIterator;
    N3Vector endpoint;
    CGFloat totalDistance;
    CFIndex segmentCount;
    
    if (N3BezierCoreHasCurve(bezierCore)) {
        flattenedBezierCore = N3BezierCoreCreateMutableCopy(bezierCore);
        N3BezierCoreFlatten((N3MutableBezierCoreRef)flattenedBezierCore, N3BezierDefaultFlatness);
    } else {
        flattenedBezierCore = N3BezierCoreRetain(bezierCore); 
    }
    
    endpoint = N3VectorZero;
    segmentCount = N3BezierCoreSegmentCount(flattenedBezierCore);
    bezierCoreIterator = N3BezierCoreIteratorCreateWithBezierCore(flattenedBezierCore);
    N3BezierCoreRelease(flattenedBezierCore);
    flattenedBezierCore = NULL;
    totalDistance = 0;
    
    while (!N3BezierCoreIteratorIsAtEnd(bezierCoreIterator)) {
        N3BezierCoreIteratorGetNextSegment(bezierCoreIterator, NULL, NULL, &endpoint);
        totalDistance += N3VectorDistanceToPlane(endpoint, plane);
    }
    
    N3BezierCoreIteratorRelease(bezierCoreIterator);
    
    return totalDistance / (CGFloat)segmentCount;
}

bool N3BezierCoreIsPlanar(N3BezierCoreRef bezierCore)
{
    N3Plane plane;
    CGFloat meanDistance;
    
    plane = N3BezierCoreLeastSquaresPlane(bezierCore);
    meanDistance = N3BezierCoreMeanDistanceToPlane(bezierCore, plane);
    
    NSLog(@"meanDistance = %f, compare to %f", meanDistance, (CGFLOAT_MIN * 1E10));
    return meanDistance < 1.0;
}















